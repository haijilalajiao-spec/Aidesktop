import SwiftUI
import AppKit

struct AIService: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case web
        case app
    }

    let id: String
    let name: String
    let subtitle: String
    let kind: Kind
    let url: String?
    let bundleID: String?
    let appPath: String?
    let symbol: String
    let tintHex: String
    let group: String

    static let webServices: [AIService] = [
        .init(id: "chatgpt", name: "ChatGPT", subtitle: "网页版", kind: .web,
              url: "https://chatgpt.com", bundleID: nil, appPath: "/Applications/ChatGPT.app",
              symbol: "sparkles", tintHex: "10A37F", group: "网页 AI"),
        .init(id: "claude", name: "Claude", subtitle: "网页版", kind: .web,
              url: "https://claude.ai/new", bundleID: nil, appPath: "/Applications/Claude.app",
              symbol: "asterisk", tintHex: "D97757", group: "网页 AI"),
        .init(id: "gemini", name: "Gemini", subtitle: "网页版", kind: .web,
              url: "https://gemini.google.com/app", bundleID: nil, appPath: "/Applications/Gemini.app",
              symbol: "diamond.fill", tintHex: "4285F4", group: "网页 AI"),
        .init(id: "grok", name: "Grok", subtitle: "网页版", kind: .web,
              url: "https://grok.com", bundleID: nil, appPath: "/Applications/Grok Bot.app",
              symbol: "bolt.fill", tintHex: "1D1D1F", group: "网页 AI"),
        .init(id: "deepseek-web", name: "DeepSeek", subtitle: "网页版", kind: .web,
              url: "https://chat.deepseek.com", bundleID: nil, appPath: "/Applications/DeepSeek Harness.app",
              symbol: "wave.3.right", tintHex: "4D6BFE", group: "网页 AI")
    ]

    static let appServices: [AIService] = [
        .init(id: "cherry", name: "Cherry Studio", subtitle: "多模型客户端", kind: .app,
              url: nil, bundleID: "com.kangfenmao.CherryStudio",
              appPath: "/Applications/Cherry Studio.app",
              symbol: "circle.hexagongrid.fill", tintHex: "EE4D6C", group: "桌面应用"),
        .init(id: "claude-app", name: "Claude", subtitle: "Claude Code 桌面版", kind: .app,
              url: nil, bundleID: "com.anthropic.claudefordesktop",
              appPath: "/Applications/Claude.app",
              symbol: "terminal.fill", tintHex: "D97757", group: "桌面应用"),
        .init(id: "chatgpt-app", name: "ChatGPT", subtitle: "Codex 桌面版", kind: .app,
              url: nil, bundleID: "com.openai.codex",
              appPath: "/Applications/ChatGPT.app",
              symbol: "terminal.fill", tintHex: "10A37F", group: "桌面应用"),
        .init(id: "gemini-app", name: "Gemini", subtitle: "桌面版", kind: .app,
              url: nil, bundleID: "com.google.GeminiMacOS",
              appPath: "/Applications/Gemini.app",
              symbol: "diamond.fill", tintHex: "4285F4", group: "桌面应用"),
        .init(id: "grok-app", name: "Grok Bot", subtitle: "桌面版", kind: .app,
              url: nil, bundleID: "com.anysphere.sand",
              appPath: "/Applications/Grok Bot.app",
              symbol: "bolt.fill", tintHex: "1D1D1F", group: "桌面应用"),
        .init(id: "deepseek-app", name: "DeepSeek Harness", subtitle: "桌面版", kind: .app,
              url: nil, bundleID: "com.deepseek.dsh",
              appPath: "/Applications/DeepSeek Harness.app",
              symbol: "wave.3.right", tintHex: "4D6BFE", group: "桌面应用"),
        .init(id: "opencode", name: "OpenCode", subtitle: "编程代理", kind: .app,
              url: nil, bundleID: "ai.opencode.desktop",
              appPath: "/Applications/OpenCode.app",
              symbol: "chevron.left.forwardslash.chevron.right", tintHex: "0A84FF", group: "编程代理"),
        .init(id: "openclaw", name: "OpenClaw", subtitle: "编程代理", kind: .app,
              url: nil, bundleID: "ai.openclaw.mac",
              appPath: "/Applications/OpenClaw.app",
              symbol: "pawprint.fill", tintHex: "FF9F0A", group: "编程代理"),
        .init(id: "plaud", name: "Plaud", subtitle: "AI 录音", kind: .app,
              url: nil, bundleID: "ai.plaud.desktop.plaud",
              appPath: "/Applications/Plaud.app",
              symbol: "waveform", tintHex: "FF6B6B", group: "桌面应用"),
        .init(id: "easydict", name: "Easydict", subtitle: "翻译", kind: .app,
              url: nil, bundleID: "com.izual.Easydict",
              appPath: "/Applications/Easydict.app",
              symbol: "character.book.closed.fill", tintHex: "5E5CE6", group: "桌面应用"),
        .init(id: "magpie", name: "Magpie", subtitle: "AI 工具", kind: .app,
              url: nil, bundleID: "com.yetone.magpie",
              appPath: "/Applications/magpie.app",
              symbol: "wand.and.stars", tintHex: "30D158", group: "桌面应用")
    ]

    static let all: [AIService] = webServices + appServices
    static let groups: [String] = ["网页 AI", "桌面应用", "编程代理"]

    func withGroup(_ group: String) -> AIService {
        AIService(
            id: id,
            name: name,
            subtitle: subtitle,
            kind: kind,
            url: url,
            bundleID: bundleID,
            appPath: appPath,
            symbol: symbol,
            tintHex: tintHex,
            group: group
        )
    }
}

enum WorkbenchPalette {
    static func primary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.96) : Color(white: 0.10)
    }

    static func secondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.72) : Color(white: 0.35)
    }
}

/// 桌面应用用软件自带图标；网页应用保留品牌色图标。
struct ServiceIcon: View {
    let service: AIService
    let size: CGFloat

    var body: some View {
        Group {
            if service.kind == .app,
               let path = service.appPath,
               FileManager.default.fileExists(atPath: path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Color(hex: service.tintHex))
                    .overlay(
                        Image(systemName: service.symbol)
                            .font(.system(size: size * 0.45, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
