import AppKit
import ApplicationServices

/// 把其他 App 的窗口“停靠”进工作台的内容区。
/// macOS 不支持跨进程窗口嵌入，这里用辅助功能 API 移动/缩放目标窗口，
/// 视觉上等同于嵌入；切换工具时恢复原窗口位置并隐藏。
@MainActor
final class WindowDocker: ObservableObject {
    static let shared = WindowDocker()

    enum Placement: String {
        case filled = "已铺满"
        case aligned = "已靠边"
        case separate = "单独打开"

        static func measured(_ frame: CGRect?, in target: CGRect) -> Placement {
            let tolerance: CGFloat = 3
            guard let frame, !frame.isEmpty,
                  abs(frame.minX - target.minX) <= tolerance,
                  abs(frame.minY - target.minY) <= tolerance,
                  frame.maxX <= target.maxX + tolerance,
                  frame.maxY <= target.maxY + tolerance else { return .separate }
            if abs(frame.maxX - target.maxX) <= tolerance &&
                abs(frame.maxY - target.maxY) <= tolerance { return .filled }
            return .aligned
        }
    }

    @Published private(set) var placement: Placement?
    @Published private(set) var dockedID: String?
    @Published private(set) var dockingID: String?
    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()
    @Published private(set) var message: String?
    @Published private(set) var needsPermission = false

    private var pid: pid_t?
    private var currentWindow: AXUIElement?
    private var savedFrame: CGRect?
    private var targetAXRect: CGRect = .zero
    private var pollTask: Task<Void, Never>?
    private var pendingPermissionID: String?
    private var canResize = true

    private init() {}

    // MARK: - Permission

    func refreshTrust() {
        let granted = AXIsProcessTrusted()
        if granted != isTrusted {
            isTrusted = granted
            Log.write("accessibility changed: trusted=\(granted)")
        }
    }

    func resumeAfterPermission(_ service: AIService) {
        guard pendingPermissionID == service.id, NSApp.isActive,
              NSApp.windows.contains(where: { $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain }) else { return }
        refreshTrust()
        if isTrusted { present(service) }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Target frame

    /// 由界面上报内容区的屏幕坐标（原点在左下角）。
    func updateTarget(_ screenRect: CGRect) {
        guard screenRect.width > 200, screenRect.height > 200 else { return }
        let ax = Self.toAX(screenRect)
        guard ax != targetAXRect else { return }
        targetAXRect = ax
        Log.write("target rect: \(ax)")
        // 在布局回调之后处理，连续移动或缩放只采用最新坐标。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.targetAXRect == ax, self.dockingID == nil,
                  let window = self.currentWindow else { return }
            self.alignCurrent(window)
        }
    }

    // MARK: - Dock

    func present(_ service: AIService) {
        guard service.kind == .app, let bundleID = service.bundleID else { return }
        if dockingID == service.id { return }
        pollTask?.cancel()
        pollTask = nil
        dockingID = nil
        message = nil
        refreshTrust()

        guard isTrusted else {
            openSeparately(service)
            pendingPermissionID = service.id
            needsPermission = true
            return
        }

        pendingPermissionID = nil
        needsPermission = false
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        if dockedID == service.id, let running, running.processIdentifier == pid,
           let window = currentWindow, let frame = Self.frame(of: window) {
            Self.show(window, in: running)
            alignCurrent(window, from: frame)
            return
        }

        if dockedID == nil { placement = nil }
        dockingID = service.id
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start.advanced(by: running == nil ? .seconds(6) : .seconds(2))
        pollTask = Task {
            // 仅在找不到窗口时轮询，现有窗口在第一轮就能完成交接。
            var requestedOpen = false
            while !Task.isCancelled {
                let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
                if let app, let window = Self.mainWindow(for: app.processIdentifier),
                   let before = Self.frame(of: window) {
                    if targetAXRect.width > 200 {
                        let sameWindow = currentWindow.map { CFEqual($0, window) } ?? false
                        let resizable = sameWindow ? canResize : Self.allowsResize(window)
                        Self.unminimize(window)
                        applyFrame(targetAXRect, to: window, from: before, resizeAllowed: resizable)
                        Self.show(window, in: app)
                        var actual = Self.frame(of: window)
                        // 有些窗口只在激活后接受定位或缩放，按实际能力再校正一次。
                        let initial = Placement.measured(actual, in: targetAXRect)
                        if initial == .separate || (initial == .aligned && resizable) {
                            applyFrame(targetAXRect, to: window, from: actual, resizeAllowed: resizable)
                            actual = Self.frame(of: window)
                        }
                        if !sameWindow {
                            restoreCurrent(hide: pid != app.processIdentifier)
                            savedFrame = before
                        }
                        pid = app.processIdentifier
                        currentWindow = window
                        canResize = resizable
                        dockingID = nil
                        let measured = Placement.measured(actual, in: targetAXRect)
                        if measured == .separate {
                            releaseToDesktop(measuredFrame: actual)
                            return
                        }
                        placement = measured
                        dockedID = service.id
                        let duration = start.duration(to: clock.now)
                        Log.write("dock done: \(service.name) \(measured.rawValue) actual=\(String(describing: actual)) target=\(targetAXRect) in \(duration)")
                        return
                    }
                } else if !requestedOpen {
                    requestedOpen = true
                    // 冷启动先在后台准备；已运行但没有窗口时向系统发送 reopen。
                    if !Launcher.launch(service, background: true) { break }
                }

                if clock.now >= deadline { break }
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            openSeparately(service)
            if message == nil { message = "暂未取得窗口，已请求系统打开 \(service.name)" }
        }
    }

    func openSeparately(_ service: AIService) {
        let sameApp = service.bundleID.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
        }?.processIdentifier == pid
        undock(hide: !sameApp)
        if !Launcher.launch(service) {
            message = "找不到 \(service.name)，请检查应用是否已安装"
        }
    }

    private static func show(_ window: AXUIElement, in app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        app.activate(options: [])
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private func restoreCurrent(hide: Bool) {
        if hide, let pid { NSRunningApplication(processIdentifier: pid)?.hide() }
        if let window = currentWindow, let saved = savedFrame {
            applyFrame(saved, to: window, resizeAllowed: canResize)
        }
    }

    /// 还原窗口并（可选）隐藏目标 App。
    func undock(hide: Bool) {
        pollTask?.cancel()
        pollTask = nil

        restoreCurrent(hide: hide)
        needsPermission = false
        pendingPermissionID = nil
        pid = nil
        currentWindow = nil
        savedFrame = nil
        dockedID = nil
        dockingID = nil
        canResize = true
        placement = nil
        message = nil
    }

    func restoreFromUI() {
        guard dockedID != nil else { return }
        undock(hide: false)
    }

    /// 工作台重新获得焦点时，把停靠窗口再抬到前面，避免被工作台窗口盖住。
    func reassertDock() {
        guard dockingID == nil, dockedID != nil, NSApp.keyWindow?.attachedSheet == nil,
              let window = currentWindow else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        alignCurrent(window)
    }

    func shutdown() {
        undock(hide: false)
    }

    private func alignCurrent(_ window: AXUIElement, from frame: CGRect? = nil) {
        applyFrame(targetAXRect, to: window, from: frame, resizeAllowed: canResize)
        var actual = Self.frame(of: window)
        // 在旧位置调整高度时，屏幕边缘可能限制尺寸。移到新位置后再校正差值。
        if canResize, let positioned = actual,
           Placement.measured(positioned, in: targetAXRect) != .filled {
            applyFrame(targetAXRect, to: window, from: positioned, resizeAllowed: true)
            actual = Self.frame(of: window)
        }
        let measured = Placement.measured(actual, in: targetAXRect)
        if measured == .separate {
            releaseToDesktop(measuredFrame: actual)
        } else if placement != measured {
            placement = measured
        }
        Log.write("dock alignment: \(measured.rawValue) actual=\(String(describing: actual)) target=\(targetAXRect)")
    }

    private func releaseToDesktop(measuredFrame: CGRect?) {
        let stillRunning = pid.flatMap { NSRunningApplication(processIdentifier: $0) }?.isTerminated == false
        undock(hide: false)
        if stillRunning {
            if measuredFrame != nil {
                placement = .separate
                message = "窗口无法放入当前内容区，已结束停靠"
            } else {
                message = "无法确认窗口位置，已结束停靠"
            }
        } else {
            message = "应用已退出"
        }
    }

    // MARK: - AX helpers

    private static func allowsResize(_ window: AXUIElement) -> Bool {
        var writable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &writable)
        return status != .success || writable.boolValue
    }

    private func applyFrame(_ rect: CGRect, to window: AXUIElement,
                            from knownFrame: CGRect? = nil, resizeAllowed: Bool) {
        let current = knownFrame ?? Self.frame(of: window)
        let resize = resizeAllowed && (current.map {
            abs($0.width - rect.width) > 1 || abs($0.height - rect.height) > 1
        } ?? true)
        if resize {
            var size = rect.size
            if let value = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
            }
        }
        // 调整大小可能带动原点，因此在 resize 后也设置一次位置。
        let move = current.map {
            abs($0.minX - rect.minX) > 1 || abs($0.minY - rect.minY) > 1
        } ?? true
        if resize || move {
            var point = rect.origin
            if let value = AXValueCreate(.cgPoint, &point) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            }
        }
    }

    // MARK: - Debug / self-test hooks

    var debugTargetAXRect: CGRect { targetAXRect }

    func debugFrame(bundleID: String) -> CGRect? {
        guard let window = debugWindow(bundleID: bundleID) else { return nil }
        return Self.frame(of: window)
    }

    func debugWindow(bundleID: String) -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        return Self.mainWindow(for: app.processIdentifier)
    }

    func debugIsHidden(bundleID: String) -> Bool? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.isHidden
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private static func unminimize(_ window: AXUIElement) {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success,
           let minimized = value as? Bool, minimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }

    private static func mainWindow(for pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)

        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value) == .success,
           let window = value {
            return (window as! AXUIElement)
        }

        value = nil
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement],
           let first = windows.first {
            return first
        }
        return nil
    }

    /// 左下角屏幕坐标 → 左上角全局坐标（AX / CGWindow 使用的坐标系）。
    private static func toAX(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
