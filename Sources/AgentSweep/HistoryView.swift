import AgentSweepCore
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<UUID> = []
    @State private var restoring: CleanRecord?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "清理记录",
                       subtitle: "每次清理都会记下文件原来的位置。只要还没清空废纸篓，就可以放回原处。注意：清空废纸篓之后，磁盘空间才会真正释放。")
            ScrollView {
                VStack(spacing: 8) {
                    if model.history.isEmpty {
                        Text("还没有清理过。").foregroundStyle(Theme.muted).padding(40)
                    }
                    ForEach(model.history) { r in row(r) }
                }
                .padding(.horizontal, 28).padding(.bottom, 20)
            }
        }
        .confirmationDialog("把这次清理的文件放回原处？", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                            titleVisibility: .visible) {
            Button("恢复") { if let r = restoring { model.restore(r) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已经从废纸篓里清空的文件无法恢复。")
        }
        .alert("macOS 不允许直接从废纸篓取回文件", isPresented: Binding(get: { !model.restoreBlocked.isEmpty }, set: { if !$0 { model.restoreBlocked = [] } })) {
            Button("在废纸篓中显示") { model.showBlockedInTrash(); model.restoreBlocked = [] }
            Button("开启完全磁盘访问权限") { model.openFullDiskAccessSettings(); model.restoreBlocked = [] }
            Button("取消", role: .cancel) { model.restoreBlocked = [] }
        } message: {
            Text("还有 \(model.restoreBlocked.count) 项在废纸篓里。可以在 Finder 中选中它们，右键选择「放回原处」；也可以在系统设置里给 AgentSweep 开启「完全磁盘访问权限」，然后回来再点一次恢复。")
        }
    }

    private func row(_ r: CleanRecord) -> some View {
        let open = expanded.contains(r.id)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.dim).frame(width: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.date, format: .dateTime.year().month().day().hour().minute())
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(r.items.count) 项 · \(r.moveCount) 个文件或文件夹").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(r.freedBytes.bytes).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                    if r.restored {
                        Text("已恢复").font(.system(size: 12, weight: .bold)).foregroundStyle(Risk.safe.color).frame(width: 70)
                    } else {
                        Button("恢复") { restoring = r }.buttonStyle(GhostButtonStyle()).frame(width: 70)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { if open { expanded.remove(r.id) } else { expanded.insert(r.id) } } }
                if open {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(r.items, id: \.ruleId) { i in
                            HStack {
                                Text(i.toolName).foregroundStyle(Theme.muted).frame(width: 90, alignment: .leading)
                                Text(i.label)
                                if !i.failures.isEmpty {
                                    Text("\(i.failures.count) 个没能移走").foregroundStyle(Risk.protected.color)
                                }
                                Spacer()
                                Text(i.bytes.bytes).monospacedDigit().foregroundStyle(Theme.muted)
                            }
                            .font(.system(size: 12))
                        }
                    }
                    .padding(.leading, 26)
                }
            }
        }
    }
}

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var unknown: [UnknownAgent]?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "规则库",
                       subtitle: "规则库 v\(model.rules.version)，更新于 \(model.rules.updated)，收录 \(model.tools.count) 个工具。每条规则写明了匹配的路径、风险等级和删除后的影响。没有写在这里的文件，AgentSweep 一律不碰。")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    unknownSection
                    userRulesSection
                    ForEach(model.tools) { t in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle().fill(t.tint).frame(width: 9, height: 9)
                                Text(t.name).font(.system(size: 15, weight: .semibold))
                                if t.shared == true {
                                    Text("多个工具共用").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }
                            }
                            ForEach(t.rules) { r in
                                Card {
                                    HStack(alignment: .top, spacing: 12) {
                                        Pill(text: r.risk.title, color: r.risk.color).frame(width: 118, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(r.label).font(.system(size: 13, weight: .semibold))
                                            Text(r.explain).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                            Text(r.paths.joined(separator: "\n")).font(Theme.mono).foregroundStyle(Theme.dim)
                                                .textSelection(.enabled)
                                        }
                                        Spacer()
                                        if r.action == .ageFilter {
                                            Text("\(model.rules.defaults.historyMaxAgeDays) 天前").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                        }
                                        if r.onlyWhen == "appMissing" {
                                            Text("仅在 App 卸载后").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
        .task {
            let rules = model.rules, home = model.home
            unknown = await Task.detached { Discovery.findUnknown(rules: rules, home: home) }.value
        }
    }

    /// Folders that look like AI tools the rules do not know yet. Shown for awareness only.
    @ViewBuilder private var unknownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Theme.ice)
                Text("可能还没收录的工具").font(.system(size: 15, weight: .semibold))
                if let u = unknown {
                    Text("\(u.count) 个 · \(u.reduce(0) { $0 + $1.bytes }.bytes)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
                }
            }
            Text("这些文件夹看起来属于某个 AI 工具，但规则库还不认识它们，所以 AgentSweep 不会清理。可以在下面的本地规则文件夹里给它们补规则。")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            if let u = unknown {
                if u.isEmpty {
                    Text("没有发现。").font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
                ForEach(u) { a in
                    Card {
                        HStack(spacing: 12) {
                            Text(abbreviate(a.path)).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                .textSelection(.enabled)
                            Text(a.reason).font(.system(size: 11)).foregroundStyle(Theme.dim)
                            Spacer()
                            Text(a.bytes.bytes).font(.system(size: 12, design: .monospaced)).monospacedDigit()
                            Button("显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: a.path)]) }
                                .buttonStyle(MiniButtonStyle())
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder private var userRulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus").foregroundStyle(Theme.ice)
                Text("本地规则").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("打开规则文件夹") {
                    let dir = RuleSet.userRulesDir
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                .buttonStyle(MiniButtonStyle())
            }
            Text("把规则文件（格式同内置的 rules.json，写成 {\"tools\": [...]}）放进规则文件夹，重启后生效。id 和内置工具相同时会替换内置规则。")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            ForEach(model.ruleErrors, id: \.self) { e in
                Label("没能读取 \(e)", systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Risk.protected.color)
            }
        }
    }
}
