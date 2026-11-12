import SwiftUI
import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var mainWindow: NSWindow?
    private var suspendedServiceID: String?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launch: AXIsProcessTrusted=\(AXIsProcessTrusted())")
        showMainWindow()
        if SelfTest.isEnabled {
            SelfTest.run()
        }
    }

    private func showMainWindow() {
        if let window = mainWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            resumeDock()
            return
        }

        let saved = Self.savedFrame()
        let frame = saved ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI 工作台"
        window.minSize = NSSize(width: 1000, height: 660)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.animationBehavior = .none
        window.backgroundColor = .windowBackgroundColor
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView())
        if let saved { window.setFrame(saved, display: false) } else { window.center() }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    /// 关闭窗口只隐藏，App 留在 Dock；再次点开是热启动，页面和登录状态都还在。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Self.saveFrame(sender.frame)
        suspendDock()
        sender.orderOut(nil)
        return false
    }

    func windowWillMiniaturize(_ notification: Notification) {
        suspendDock()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        resumeDock()
    }

    private func suspendDock() {
        let docker = WindowDocker.shared
        guard let id = docker.dockingID ?? docker.dockedID else { return }
        suspendedServiceID = id
        docker.undock(hide: true)
    }

    private func resumeDock() {
        guard let id = suspendedServiceID else { return }
        suspendedServiceID = nil
        NotificationCenter.default.post(name: .workbenchResumeDock, object: id)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let window = mainWindow { Self.saveFrame(window.frame) }
        WindowDocker.shared.shutdown()
    }

    // MARK: - Window frame persistence

    private static let frameKey = "AIWorkbench.MainWindowFrame"

    private static func savedFrame() -> NSRect? {
        guard let raw = UserDefaults.standard.string(forKey: frameKey) else { return nil }
        let rect = NSRectFromString(raw)
        guard rect.width >= 1000, rect.height >= 660 else { return nil }
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
        return visible ? rect : nil
    }

    private static func saveFrame(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: frameKey)
    }
}

@main
struct AIWorkbenchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandMenu("工作台") {
                Button("一键启动全部桌面应用") {
                    NotificationCenter.default.post(name: .workbenchLaunchAll, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("刷新当前页面") {
                    NotificationCenter.default.post(name: .workbenchReload, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let workbenchLaunchAll = Notification.Name("workbenchLaunchAll")
    static let workbenchResumeDock = Notification.Name("workbenchResumeDock")
    static let workbenchReload = Notification.Name("workbenchReload")
}
