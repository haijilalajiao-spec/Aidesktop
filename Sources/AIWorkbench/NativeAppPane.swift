import SwiftUI
import AppKit

struct NativeAppPane: View {
    let service: AIService
    @ObservedObject var docker: WindowDocker
    @ObservedObject var services: ServiceStore

    @State private var isRunning = false
    @State private var showRemoveConfirm = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            appIcon
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)

            VStack(spacing: 7) {
                Text(service.name)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                Text(service.subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                Text(service.appPath ?? "")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                Button {
                    docker.refreshTrust()
                    if docker.isTrusted { docker.present(service) }
                    else { docker.openAccessibilitySettings() }
                } label: {
                    Label(docker.isTrusted ? "在工作台内打开" : "打开辅助功能设置…",
                          systemImage: "rectangle.inset.filled")
                        .frame(minWidth: 128)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    docker.openSeparately(service)
                } label: {
                    Label("单独打开", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if docker.dockingID == service.id {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在启动 \(service.name)…")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } else if docker.dockedID == service.id {
                Label(docker.placement == .aligned ? "已靠边，保留当前窗口尺寸" : "已铺满右侧内容区", systemImage: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if docker.needsPermission || !docker.isTrusted {
                permissionCard
            } else {
                statusLine
            }

            if let message = docker.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button(role: .destructive) {
                showRemoveConfirm = true
            } label: {
                Label(
                    services.isCustom(service.id) ? "从工作台移除" : "从工作台隐藏",
                    systemImage: "trash"
                )
                .font(.system(size: 12))
            }
            .buttonStyle(.link)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .onAppear(perform: refreshStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
            docker.resumeAfterPermission(service)
            docker.refreshTrust()
        }
        .task(id: service.id) {
            while !Task.isCancelled && docker.needsPermission {
                docker.resumeAfterPermission(service)
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .alert("从工作台移除 \(service.name)？", isPresented: $showRemoveConfirm) {
            Button("移除", role: .destructive) {
                services.remove(id: service.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("不会卸载应用，只是从侧栏移除。内置应用之后可恢复。")
        }
    }

    private var permissionCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "lock.shield")
                Text("macOS 尚未允许这个版本调整窗口。若开关已打开，请从列表移除旧条目，再用「＋」添加当前工作台。")
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("在 Finder 中定位当前工作台") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .buttonStyle(.bordered)

                Button("已授权，重新检测") {
                    docker.refreshTrust()
                    if docker.isTrusted { docker.present(service) }
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var appIcon: some View {
        Group {
            if let path = service.appPath, FileManager.default.fileExists(atPath: path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: service.symbol)
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(Color(hex: service.tintHex))
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(isRunning ? "正在运行" : "未运行")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.tertiary)
            Button("在 Finder 中显示") {
                Launcher.reveal(service)
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(hex: service.tintHex).opacity(0.12), Color(nsColor: .windowBackgroundColor)],
            startPoint: .top, endPoint: .center
        )
        .ignoresSafeArea()
    }

    private func refreshStatus() {
        guard let bundleID = service.bundleID else { isRunning = false; return }
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
