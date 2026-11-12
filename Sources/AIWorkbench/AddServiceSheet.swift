import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddServiceSheet: View {
    @ObservedObject var services: ServiceStore
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable {
        case app = "桌面应用"
        case web = "网页"
    }

    @State private var mode: Mode = .app
    @State private var name = ""
    @State private var urlString = ""
    @State private var selectedAppURL: URL?
    @State private var bundleID: String?
    @State private var group = "我的应用"
    @State private var newGroupName = ""
    @State private var errorMessage: String?

    private let palette = ["5E5CE6", "FF9F0A", "30D158", "64D2FF", "FF453A", "BF5AF2", "FFD60A"]
    private let newGroupTag = "__new_group__"

    private var groupOptions: [String] {
        var options = services.groups
        if !options.contains("我的应用") {
            options.insert("我的应用", at: 0)
        }
        return options
    }

    private var finalGroup: String {
        if group == newGroupTag {
            return newGroupName.trimmingCharacters(in: .whitespaces)
        }
        return group
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加应用")
                .font(.system(size: 17, weight: .semibold))

            Picker("类型", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .app {
                appFields
            } else {
                webFields
            }

            HStack(spacing: 10) {
                Text("分组")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Picker("分组", selection: $group) {
                    ForEach(groupOptions, id: \.self) { Text($0).tag($0) }
                    Text("＋ 新建分组…").tag(newGroupTag)
                }
                .labelsHidden()
                .frame(width: 150)

                if group == newGroupTag {
                    TextField("新分组名称", text: $newGroupName)
                        .frame(width: 150)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加") { add() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onChange(of: mode) { _ in errorMessage = nil }
    }

    private var appFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("选择应用程序…") { chooseApp() }

            if let url = selectedAppURL {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(.system(size: 13, weight: .medium))
                        Text(url.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                TextField("显示名称", text: $name)
            } else {
                Text("选择 .app 后会自动填入名称")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var webFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("名称，例如 Kimi", text: $name)
            TextField("网址，例如 example.com", text: $urlString)
            if !urlString.isEmpty && webURL == nil {
                Text("请输入域名或完整的 HTTP、HTTPS 网址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var webURL: URL? { WebAddress.parse(urlString) }

    private var canAdd: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if group == newGroupTag && newGroupName.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        switch mode {
        case .app:
            return selectedAppURL != nil
        case .web:
            return webURL != nil
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedAppURL = url
        let bundle = Bundle(url: url)
        bundleID = bundle?.bundleIdentifier
        if name.isEmpty {
            name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
        }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let tint = palette.randomElement() ?? "5E5CE6"
        let targetGroup = finalGroup
        guard !targetGroup.isEmpty else {
            errorMessage = "请填写分组名称"
            return
        }

        switch mode {
        case .app:
            guard let url = selectedAppURL, let bundleID else { return }
            if services.restoreIfHidden(bundleID: bundleID) {
                dismiss()
                return
            }
            if services.contains(bundleID: bundleID) {
                errorMessage = "这个应用已经在工作台里了"
                return
            }
            services.add(
                AIService(
                    id: "custom-\(UUID().uuidString)",
                    name: trimmed,
                    subtitle: "自定义应用",
                    kind: .app,
                    url: nil,
                    bundleID: bundleID,
                    appPath: url.path,
                    symbol: "app.fill",
                    tintHex: tint,
                    group: targetGroup
                )
            )

        case .web:
            guard let url = webURL, let host = url.host else { return }
            if services.contains(url: url) {
                errorMessage = "这个网址已经在工作台里了"
                return
            }
            services.add(
                AIService(
                    id: "custom-\(UUID().uuidString)",
                    name: trimmed,
                    subtitle: host,
                    kind: .web,
                    url: url.absoluteString,
                    bundleID: nil,
                    appPath: nil,
                    symbol: "globe",
                    tintHex: tint,
                    group: targetGroup
                )
            )
        }

        dismiss()
    }
}
