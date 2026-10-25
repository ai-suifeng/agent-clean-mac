import AgentSweepCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 236)
            Rectangle().fill(Theme.line).frame(width: 1)
            Group {
                switch model.section {
                case .clean: CleanView()
                case .sessions: SessionsView()
                case .compact: CompactView()
                case .history: HistoryView()
                case .rules: RulesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Backdrop())
        .foregroundStyle(Theme.fg)
        .overlay(alignment: .bottom) { ToastView() }
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }
}

struct Backdrop: View {
    var body: some View {
        ZStack {
            Theme.window
            RadialGradient(colors: [Theme.ice2.opacity(0.12), .clear], center: .init(x: 0.55, y: -0.1), startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Theme.violet.opacity(0.06), .clear], center: .init(x: 0.95, y: 1.1), startRadius: 0, endRadius: 600)
        }
        .ignoresSafeArea()
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Logo().frame(width: 26, height: 26)
                Text("AgentSweep").font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 10)
            .padding(.top, 44)

            VStack(spacing: 2) {
                ForEach(Section.allCases) { s in
                    NavButton(section: s, on: model.section == s) { model.section = s }
                }
            }

            Text("已检测到的工具")
                .font(.system(size: 10.5, weight: .bold)).kerning(1.2)
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 10)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(model.tools) { t in ToolRow(tool: t, report: model.reports[t.id]) }
                }
            }
            .scrollIndicators(.never)

            VersionFooter()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel.opacity(0.45))
    }
}

struct VersionFooter: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        HStack(spacing: 8) {
            Text("v\(updater.version)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dim)
            Spacer()
            if Updater.isConfigured {
                Button("检查更新") { updater.checkForUpdates() }
                    .buttonStyle(MiniButtonStyle())
                    .disabled(!updater.canCheck)
            }
        }
        .padding(.horizontal, 10)
    }
}

struct Logo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AngularGradient(colors: [Theme.ice, Theme.violet, Theme.ice2, Theme.ice], center: .center, angle: .degrees(200)))
            Circle().fill(.black).padding(7)
        }
        .shadow(color: Theme.ice.opacity(0.35), radius: 9)
    }
}

struct NavButton: View {
    let section: Section
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon).frame(width: 18)
                Text(section.title)
                Spacer()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on || hover ? Theme.fg : Theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [Theme.ice.opacity(0.14), Theme.ice.opacity(0.04)], startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.ice.opacity(0.18)))
                } else if hover {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.raise)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ToolRow: View {
    let tool: ToolDef
    let report: ToolReport?

    var body: some View {
        let lit = report != nil
        HStack(spacing: 9) {
            Circle().fill(tool.tint).frame(width: 8, height: 8)
                .opacity(lit ? 1 : 0.3)
                .shadow(color: lit ? tool.tint : .clear, radius: 5)
            Text(tool.name).foregroundStyle(lit ? Theme.fg : Theme.muted).lineLimit(1)
            if report?.appMissing == true {
                Text("已卸载").font(.system(size: 10)).foregroundStyle(Theme.violet).fixedSize()
            }
            Spacer(minLength: 4)
            Text(report.map { $0.bytes.bytes } ?? "—")
                .font(Theme.mono).monospacedDigit()
                .foregroundStyle(Theme.dim)
                .fixedSize()
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .animation(.easeOut(duration: 0.3), value: lit)
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let t = model.toast {
            Text(t)
                .font(.system(size: 13))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Theme.raise, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line2))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                .padding(.bottom, 84)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Shared page header for the secondary sections.
struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(subtitle).font(.system(size: 13.5)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 12)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
    }
}
