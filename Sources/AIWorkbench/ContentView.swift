import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Launcher {
    @discardableResult
    static func launch(_ service: AIService, background: Bool = false) -> Bool {
        let installed = service.appPath.flatMap { path in
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        guard let url = installed ?? service.bundleID.flatMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:)) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = !background
        configuration.hides = background && service.bundleID.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
        } == nil
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { Log.write("open failed: \(service.name) \(error.localizedDescription)") }
        }
        return true
    }

    static func reveal(_ service: AIService) {
        guard let path = service.appPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func launchAllApps(_ apps: [AIService]) {
        for service in apps {
            launch(service)
        }
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: String? = "chatgpt"
    @State private var displayedSelection: String? = "chatgpt"
    @State private var slowLaunchID: String?
    @State private var showAddSheet = false
    @State private var renameTarget: RenameTarget?
    @StateObject private var services = ServiceStore()
    @StateObject private var store = WebViewStore()
    @StateObject private var docker = WindowDocker.shared

    private var selectedService: AIService? {
        services.services.first { $0.id == selection }
    }

    private var displayedService: AIService? {
        services.services.first { $0.id == displayedSelection }
    }

    var body: some View {
        // 固定左右布局，首帧即最终布局，启动不做任何宽度动画
        HStack(spacing: 0) {
            sidebar
                .frame(width: 228)
            Divider()
            VStack(spacing: 0) {
                header
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DetailFrameReporter { docker.updateTarget($0) })
                    .allowsHitTesting(displayedSelection == selection)
            }
        }
        .frame(minWidth: 1000, minHeight: 660)
        .onAppear {
            if selectedService == nil { selection = services.defaultWebID }
            else { syncSelection() }
        }
        .onChange(of: services.services.map(\.id)) { ids in
            store.retainServices(Set(ids))
            if let selection, !ids.contains(selection) { self.selection = services.defaultWebID }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workbenchLaunchAll)) { _ in
            Launcher.launchAllApps(services.desktopServices)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workbenchResumeDock)) { notification in
            if let id = notification.object as? String, selection == id { syncSelection() }
        }
        .onChange(of: selection) { _ in syncSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .workbenchReload)) { _ in
            if let service = selectedService, service.kind == .web {
                store.reload(service)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            docker.refreshTrust()
            docker.reassertDock()
        }
        .onChange(of: docker.dockedID) { id in
            if let id, id == selection { displayedSelection = id }
        }
        .task(id: docker.dockingID) {
            slowLaunchID = nil
            guard let id = docker.dockingID else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            if docker.dockingID == id { slowLaunchID = id }
        }
        .onChange(of: docker.message) { message in
            if message != nil, let selection { displayedSelection = selection }
        }
        .sheet(isPresented: $showAddSheet) {
            AddServiceSheet(services: services)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(services.groups, id: \.self) { group in
                    let collapsed = services.isCollapsed(group)
                    Section {
                        if !collapsed {
                            ForEach(services.services(in: group)) { service in
                            SidebarRow(service: service)
                                .tag(service.id)
                                .id(service.id)
                                .contextMenu {
                                    Button("上移") {
                                        services.move(id: service.id, in: group, delta: -1)
                                    }
                                    Button("下移") {
                                        services.move(id: service.id, in: group, delta: 1)
                                    }
                                    Menu("移动到分组") {
                                        ForEach(services.groups, id: \.self) { target in
                                            Button {
                                                services.moveToGroup(id: service.id, group: target)
                                            } label: {
                                                if service.group == target {
                                                    Label(target, systemImage: "checkmark")
                                                } else {
                                                    Text(target)
                                                }
                                            }
                                        }
                                    }
                                    Divider()
                                    Button(
                                        services.isCustom(service.id) ? "从工作台移除" : "从工作台隐藏",
                                        role: .destructive
                                    ) {
                                        services.remove(id: service.id)
                                    }
                                }
                        }
                            .onMove { indices, newOffset in
                                services.move(in: group, from: indices, to: newOffset)
                            }
                        }
                    } header: {
                        GroupHeader(
                            group: group,
                            collapsed: collapsed,
                            count: services.services(in: group).count,
                            colorScheme: colorScheme,
                            canMoveUp: services.groups.first != group,
                            canMoveDown: services.groups.last != group,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    services.toggleCollapsed(group)
                                }
                            },
                            onMoveUp: { services.moveGroup(group, delta: -1) },
                            onMoveDown: { services.moveGroup(group, delta: 1) },
                            onRename: { renameTarget = RenameTarget(name: group) },
                            onDropService: { id in
                                services.moveToGroup(id: id, group: group)
                            }
                        )
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: services.custom.count) { _ in
                guard let id = services.custom.last?.id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .sheet(item: $renameTarget) { target in
                RenameGroupSheet(group: target.name, services: services)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                Divider()

                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加应用…")
                        Spacer()
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 10))
                    Text("\(services.services.count) 个工具 · 拖动排序")
                        .font(.system(size: 11))
                    Spacer()
                }
                .foregroundStyle(WorkbenchPalette.secondary(for: colorScheme))
                .padding(.horizontal, 14)

                if !services.hiddenBuiltins.isEmpty {
                    Button("恢复已隐藏的 \(services.hiddenBuiltins.count) 个应用") {
                        services.restoreHidden()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }

                Color.clear.frame(height: 8)
            }
            .background(.bar)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let service = displayedService {
            switch service.kind {
            case .app:
                NativeAppPane(service: service, docker: docker, services: services)
            case .web:
                webStack(for: service)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("从左侧选择一个 AI 工具")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func webStack(for service: AIService) -> some View {
        ZStack {
            ForEach(store.created, id: \.self) { id in
                if let webView = store.view(for: id) {
                    WebViewContainer(webView: webView)
                        .opacity(displayedSelection == id ? 1 : 0)
                        .allowsHitTesting(selection == id)
                        .accessibilityHidden(displayedSelection != id)
                }
            }

            if !store.has(service.id) || store.isLoading(service.id) {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在打开 \(service.name)…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .transition(.opacity)
                .zIndex(2)
            }

            if let status = store.httpError(service.id) {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(status > 0
                             ? "网页返回 HTTP \(status)，可能被网站或代理拒绝"
                             : "页面加载失败或超时")
                            .font(.system(size: 12))
                        Spacer()
                        Button("重试") {
                            store.reload(service)
                        }
                        .buttonStyle(.borderless)
                        Button("用浏览器打开") {
                            store.openInBrowser(service)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                    )
                    .padding(12)

                    Spacer()
                }
                .zIndex(3)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.isLoading(service.id))
        .animation(.easeInOut(duration: 0.18), value: selection)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            if let service = selectedService {
                HStack(spacing: 8) {
                    ServiceIcon(service: service, size: 22)
                    Text(service.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WorkbenchPalette.primary(for: colorScheme))
                }
            }

            if let service = selectedService, service.kind == .app,
               docker.dockingID == nil, let placement = docker.placement,
               docker.dockedID == service.id || placement == .separate {
                Text(placement.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let id = slowLaunchID, id == docker.dockingID {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("正在打开应用")
            }

            Spacer()

            if let service = selectedService, service.kind == .web {
                headerButton("arrow.clockwise", "刷新") {
                    store.reload(service)
                }
                headerButton("house", "回到首页") {
                    store.goHome(service)
                }
                headerButton("safari", "用默认浏览器打开") {
                    store.openInBrowser(service)
                }
                Divider().frame(height: 15)
            }

            if let id = docker.dockedID, id == selection {
                headerButton("rectangle.portrait.and.arrow.right", "把停靠的窗口还原到原位置") {
                    docker.restoreFromUI()
                }
                Divider().frame(height: 15)
            }

            Button {
                Launcher.launchAllApps(services.desktopServices)
            } label: {
                Label("启动全部", systemImage: "power")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.borderless)
            .help("一键启动全部桌面应用")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func headerButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func syncSelection() {
        guard let service = selectedService else {
            docker.undock(hide: true)
            displayedSelection = nil
            return
        }
        if service.kind == .web {
            store.ensure(service)
            docker.undock(hide: true)
            displayedSelection = service.id
        } else {
            docker.present(service)
            if docker.dockingID == nil { displayedSelection = service.id }
        }
    }
}

/// 上报内容区的屏幕坐标，窗口停靠时用来精确对齐。
struct DetailFrameReporter: NSViewRepresentable {
    let onFrame: (CGRect) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onFrame = onFrame
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: ReportingView, context: Context) {
        nsView.onFrame = onFrame
        nsView.report()
    }

    final class Coordinator {
        weak var view: ReportingView?
        private var tokens: [NSObjectProtocol] = []

        init() {
            let center = NotificationCenter.default
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.view?.report()
                })
            }
        }

        deinit {
            tokens.forEach(NotificationCenter.default.removeObserver)
        }
    }

    /// 用真实 NSView 的 viewDidMoveToWindow / layout 时机上报，
    /// 避免 SwiftUI 里 window 尚未挂载导致永远拿不到坐标。
    final class ReportingView: NSView {
        var onFrame: ((CGRect) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        override func layout() {
            super.layout()
            report()
        }

        func report() {
            guard let window, window.windowNumber > 0 else { return }
            let inWindow = convert(bounds, to: nil)
            let screenRect = window.convertToScreen(inWindow)
            onFrame?(screenRect)
        }
    }
}

struct SidebarRow: View {
    let service: AIService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            ServiceIcon(service: service, size: 27)

            VStack(alignment: .leading, spacing: 1) {
                Text(service.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WorkbenchPalette.primary(for: colorScheme))
                Text(service.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WorkbenchPalette.secondary(for: colorScheme))
            }

            Spacer(minLength: 4)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WorkbenchPalette.secondary(for: colorScheme).opacity(0.4))
                .frame(width: 16, height: 18)
                .contentShape(Rectangle())
                .onDrag {
                    NSItemProvider(object: service.id as NSString)
                }
                .help("拖到其他分组")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct RenameTarget: Identifiable {
    let name: String
    var id: String { name }
}

private struct GroupHeader: View {
    let group: String
    let collapsed: Bool
    let count: Int
    let colorScheme: ColorScheme
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggle: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRename: () -> Void
    let onDropService: (String) -> Void

    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 10)

            Text(group)
                .font(.system(size: 11, weight: .semibold))

            Spacer()

            Text("\(count)")
                .font(.system(size: 10))
                .foregroundStyle(WorkbenchPalette.secondary(for: colorScheme).opacity(0.7))
        }
        .foregroundStyle(WorkbenchPalette.secondary(for: colorScheme))
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .onTapGesture(perform: onToggle)
        .contextMenu {
            Button("上移分组", action: onMoveUp)
                .disabled(!canMoveUp)
            Button("下移分组", action: onMoveDown)
                .disabled(!canMoveDown)
            Divider()
            Button("重命名分组…", action: onRename)
        }
        .onDrop(of: [UTType.text], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let id = object as? String else { return }
                DispatchQueue.main.async { onDropService(id) }
            }
            return true
        }
        .help(collapsed ? "展开分组" : "折叠分组")
    }
}
