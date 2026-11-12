import AppKit
import ApplicationServices

/// 用 `--self-test` 启动时运行：自动把目标 App 停靠进内容区并校验坐标。
/// 可用 `--self-test-app <bundleID> <path> <name>` 指定测试目标，
/// 默认用 TextEdit（可自由调整窗口大小）。
@MainActor
enum SelfTest {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--self-test")
    }

    private struct TestTarget {
        let bundleID: String
        let path: String
        let name: String
        let sampleFile: String?
    }

    static func run() {
        Task { await execute() }
    }

    private static func target() -> TestTarget {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--self-test-app"), index + 3 < args.count {
            return TestTarget(
                bundleID: args[index + 1],
                path: args[index + 2],
                name: args[index + 3],
                sampleFile: nil
            )
        }
        return TestTarget(
            bundleID: "com.apple.TextEdit",
            path: "/System/Applications/TextEdit.app",
            name: "TextEdit",
            sampleFile: "/tmp/aiw-selftest.txt"
        )
    }

    private static func execute() async {
        Log.write("SELFTEST start trusted=\(AXIsProcessTrusted())")
        let docker = WindowDocker.shared

        if !AXIsProcessTrusted() {
            docker.openAccessibilitySettings()
            Log.write("SELFTEST waiting for accessibility permission (up to 120s)...")
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if AXIsProcessTrusted() { break }
            }
        }

        guard AXIsProcessTrusted() else {
            Log.write("SELFTEST FAIL: no accessibility permission")
            return
        }

        var waited = 0
        while docker.debugTargetAXRect.width < 200 && waited < 40 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        let targetRect = docker.debugTargetAXRect
        Log.write("SELFTEST target rect=\(targetRect)")
        guard targetRect.width > 200 else {
            Log.write("SELFTEST FAIL: target rect not ready")
            return
        }

        let testTarget = target()
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: testTarget.bundleID).isEmpty

        if !wasRunning {
            if let sample = testTarget.sampleFile {
                try? "AI Workbench self test".write(toFile: sample, atomically: true, encoding: .utf8)
                _ = try? await NSWorkspace.shared.open(
                    [URL(fileURLWithPath: sample)],
                    withApplicationAt: URL(fileURLWithPath: testTarget.path),
                    configuration: NSWorkspace.OpenConfiguration()
                )
            } else {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: testTarget.path),
                    configuration: configuration
                ) { _, _ in }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        // 等窗口出现
        var windowWait = 0
        while docker.debugFrame(bundleID: testTarget.bundleID) == nil && windowWait < 40 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            windowWait += 1
        }

        let before = docker.debugFrame(bundleID: testTarget.bundleID)
        Log.write("SELFTEST \(testTarget.name) before=\(String(describing: before))")

        if let window = docker.debugWindow(bundleID: testTarget.bundleID) {
            var settable: DarwinBoolean = false
            let error = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)
            Log.write("SELFTEST sizeSettable=\(settable.boolValue) err=\(error.rawValue)")
        }

        let service = AIService(
            id: "selftest-target",
            name: testTarget.name,
            subtitle: "self test",
            kind: .app,
            url: nil,
            bundleID: testTarget.bundleID,
            appPath: testTarget.path,
            symbol: "app.fill",
            tintHex: "888888",
            group: "selftest"
        )

        docker.present(service)
        for _ in 0..<70 {
            if docker.dockingID == nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        let after = docker.debugFrame(bundleID: testTarget.bundleID)
        let placement = docker.placement
        if placement == .separate {
            let restored = before != nil && before == after && docker.dockedID == nil
            Log.write("SELFTEST standalone restored=\(restored) -> \(restored ? "PASS" : "FAIL")")
        } else {
            let measured = WindowDocker.Placement.measured(after, in: docker.debugTargetAXRect)
            let docked = docker.dockedID == service.id && measured != .separate && measured == placement
            Log.write("SELFTEST dock placement=\(placement?.rawValue ?? "-") frame=\(String(describing: after)) -> \(docked ? "PASS" : "FAIL")")

            if docked && ProcessInfo.processInfo.arguments.contains("--self-test-resize") {
                await checkResize(bundleID: testTarget.bundleID, docker: docker)
            }
            docker.undock(hide: true)
            try? await Task.sleep(for: .milliseconds(700))
            let hidden = docker.debugIsHidden(bundleID: testTarget.bundleID) ?? false
            let restored = before != nil && before == docker.debugFrame(bundleID: testTarget.bundleID)
            Log.write("SELFTEST undock hidden=\(hidden) restored=\(restored) -> \(hidden && restored ? "PASS" : "FAIL")")
        }

        if wasRunning, let app = NSRunningApplication.runningApplications(withBundleIdentifier: testTarget.bundleID).first {
            app.unhide()
        }
        if !wasRunning {
            NSRunningApplication.runningApplications(withBundleIdentifier: testTarget.bundleID).first?.terminate()
        }

        if ProcessInfo.processInfo.arguments.contains("--self-test-resize") {
            Log.write("SELFTEST done")
            return
        }
        // 自定义存储增删
        let store = ServiceStore()
        let custom = AIService(
            id: "selftest-custom",
            name: "SelfTest",
            subtitle: "example.com",
            kind: .web,
            url: "https://example.com",
            bundleID: nil,
            appPath: nil,
            symbol: "globe",
            tintHex: "5E5CE6",
            group: "我的应用"
        )
        let beforeCount = store.custom.count
        store.add(custom)
        let added = store.custom.count == beforeCount + 1
        store.remove(id: custom.id)
        let removed = !store.custom.contains { $0.id == custom.id }
        Log.write("SELFTEST custom add=\(added) remove=\(removed) -> \(added && removed ? "PASS" : "FAIL")")

        Log.write("SELFTEST done")
    }
    private static func checkResize(bundleID: String, docker: WindowDocker) async {
        guard let host = NSApp.windows.first(where: { $0.title == "AI 工作台" }) else {
            Log.write("SELFTEST resize FAIL: host missing")
            return
        }
        let original = host.frame
        let originalTarget = docker.debugTargetAXRect
        defer { host.setFrame(original, display: true) }
        var smaller = original
        smaller.size.width = max(host.minSize.width, original.width - 150)
        smaller.size.height = max(host.minSize.height, original.height - 90)

        func check(_ name: String) async {
            let expected = CGRect(x: originalTarget.minX,
                                  y: originalTarget.minY + original.height - host.frame.height,
                                  width: originalTarget.width + host.frame.width - original.width,
                                  height: originalTarget.height + host.frame.height - original.height)
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(50))
                let actual = docker.debugFrame(bundleID: bundleID)
                if docker.dockedID != nil, WindowDocker.Placement.measured(actual, in: expected) == .filled {
                    Log.write("SELFTEST resize \(name) expected=\(expected) actual=\(String(describing: actual)) -> PASS")
                    return
                }
            }
            Log.write("SELFTEST resize \(name) expected=\(expected) actual=\(String(describing: docker.debugFrame(bundleID: bundleID))) -> FAIL")
        }

        host.setFrame(smaller, display: true)
        await check("shrink")
        for step in 1...10 {
            let progress = CGFloat(step) / 10
            var frame = smaller
            frame.size.width += (original.width - smaller.width) * progress
            frame.size.height += (original.height - smaller.height) * progress
            host.setFrame(frame, display: true)
            try? await Task.sleep(for: .milliseconds(20))
        }
        await check("grow")
    }

}
