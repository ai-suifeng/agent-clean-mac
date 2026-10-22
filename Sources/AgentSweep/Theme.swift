import SwiftUI
import AgentSweepCore

enum Theme {
    static let space = Color(hex: "#05070D")
    static let window = Color(hex: "#0B0F1A")
    static let panel = Color(hex: "#111726")
    static let raise = Color(hex: "#161D2F")
    static let line = Color(red: 170 / 255, green: 190 / 255, blue: 1).opacity(0.09)
    static let line2 = Color(red: 170 / 255, green: 190 / 255, blue: 1).opacity(0.16)
    static let fg = Color(hex: "#E6EBF7")
    static let muted = Color(hex: "#8892AC")
    static let dim = Color(hex: "#5A6380")
    static let ice = Color(hex: "#8FD8FF")
    static let ice2 = Color(hex: "#5BA8FF")
    static let violet = Color(hex: "#C084FC")

    static let cta = LinearGradient(colors: [Color(hex: "#B5E6FF"), ice, ice2], startPoint: .top, endPoint: .bottom)
    static let mono = Font.system(size: 11, design: .monospaced)
}

extension Risk {
    static let order: [Risk] = [.orphan, .safe, .history, .compact, .protected]

    var title: String {
        switch self {
        case .orphan: "已卸载工具残留"
        case .safe: "可安全删除"
        case .history: "旧会话与历史"
        case .compact: "数据库 · 仅压缩"
        case .protected: "受保护"
        }
    }

    var blurb: String {
        switch self {
        case .orphan: "App 已经删了，数据还留着"
        case .safe: "缓存、日志、临时文件，删除后会自动重建"
        case .history: "30 天没动过的记录，可以先导出再删除"
        case .compact: "不能删除，退出对应工具后可以压缩"
        case .protected: "配置、登录凭证和技能，不会触碰"
        }
    }

    var color: Color {
        switch self {
        case .orphan: Color(hex: "#C084FC")
        case .safe: Color(hex: "#4ADE80")
        case .history: Color(hex: "#FACC15")
        case .compact: Color(hex: "#FB923C")
        case .protected: Color(hex: "#F87171")
        }
    }

    /// Ring color; protected items recede so the ring reads as "what you can act on".
    var ringColor: Color { self == .protected ? Color(hex: "#2E3650") : color }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Foundation.Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension ToolDef {
    var tint: Color { Color(hex: color) }
}

extension Int64 {
    var bytes: String { ByteFormat.string(self) }
}

struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.9), lineWidth: 1))
            .fixedSize()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color(hex: "#04121D"))
            .padding(.horizontal, 22).padding(.vertical, 11)
            .background(Theme.cta, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Theme.ice2.opacity(enabled ? 0.55 : 0), radius: 16, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? Theme.fg : Theme.muted)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line2, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(configuration.isPressed ? Theme.ice : Theme.fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line2, lineWidth: 1))
            .contentShape(Rectangle())
    }
}
