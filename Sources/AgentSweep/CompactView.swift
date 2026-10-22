import AgentSweepCore
import SwiftUI

struct DBRow: Identifiable {
    var id: String { path }
    let path: String
    let tool: ToolDef
    let label: String
    var stats: DBStats?
    var running: Bool
    var result: String?
    var busy = false
}

struct CompactView: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [DBRow] = []
    @State private var loading = true
    @State private var backupBytes: Int64 = 0

    private var backupDir: URL { AppPaths.support.appendingPathComponent("backups") }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "数据库压缩",
                       subtitle: "这些数据库保存着聊天记录，不能删除。退出对应工具后，AgentSweep 会先完整备份，再用 VACUUM 收回空闲空间。能收回多少取决于数据库里有多少空闲页，下面的数字是实测值。")
            ScrollView {
                VStack(spacing: 8) {
                    if loading {
                        ProgressView().padding(40)
                    } else if rows.isEmpty {
                        Text("没有找到可以压缩的数据库。").foregroundStyle(Theme.muted).padding(40)
                    }
                    ForEach($rows) { $row in DBRowView(row: $row, compact: { compact(row.path) }) }
                }
                .padding(.horizontal, 28)
            }
            backups
        }
        .task { await load() }
    }

    private var backups: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("压缩前的备份 · \(backupBytes.bytes)").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("确认工具运行正常后，可以删掉这些备份。").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("刷新") { Task { await load() } }.buttonStyle(GhostButtonStyle())
            Button("在 Finder 中显示") {
                try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
                NSWorkspace.shared.open(backupDir)
            }
            .buttonStyle(GhostButtonStyle())
            Button("备份移到废纸篓") {
                let files = (try? FileManager.default.contentsOfDirectory(atPath: backupDir.path)) ?? []
                let record = Cleaner.trashFiles(files.map { backupDir.appendingPathComponent($0).path },
                                                label: "数据库备份", toolName: "数据库压缩", bytes: backupBytes)
                try? model.historyStore.save(record)
                model.history = model.historyStore.load()
                backupBytes = 0
                model.show("备份已移到废纸篓")
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(backupBytes == 0)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Theme.panel.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func load() async {
        loading = true
        let rules = model.rules
        let home = model.home
        let dir = backupDir
        let (found, backup) = await Task.detached { () -> ([DBRow], Int64) in
            let scanner = AgentSweepCore.Scanner(rules: rules, home: home)
            let procs = ProcessDetector.executablePaths()
            var out: [DBRow] = []
            for tool in rules.tools where tool.rules.contains(where: { $0.action == .vacuum }) {
                guard let report = scanner.scan(tool) else { continue }
                for f in report.findings where f.risk == .compact {
                    for p in f.entries {
                        out.append(DBRow(path: p, tool: tool, label: f.rule.label, stats: try? SQLiteCompactor.stats(p),
                                         running: ProcessDetector.isRunning(tool, paths: procs)))
                    }
                }
            }
            return (out.sorted { ($0.stats?.fileBytes ?? 0) > ($1.stats?.fileBytes ?? 0) }, DiskUsage.measure(dir.path).bytes)
        }.value
        rows = found
        backupBytes = backup
        loading = false
    }

    private func compact(_ path: String) {
        guard let i = rows.firstIndex(where: { $0.path == path }) else { return }
        let tool = rows[i].tool
        if ProcessDetector.isRunning(tool) {
            rows[i].running = true
            model.show("\(tool.name) 还在运行，请先退出再压缩。")
            return
        }
        rows[i].busy = true
        Task {
            let outcome = await Task.detached { Result { try SQLiteCompactor.compact(path) } }.value
            guard let j = rows.firstIndex(where: { $0.path == path }) else { return }
            rows[j].busy = false
            switch outcome {
            case .success(let r):
                rows[j].result = "\(r.before.bytes) → \(r.after.bytes)，收回 \(max(0, r.before - r.after).bytes)"
                rows[j].stats = try? SQLiteCompactor.stats(path)
                backupBytes = DiskUsage.measure(backupDir.path).bytes
            case .failure(let e):
                rows[j].result = e.localizedDescription
            }
        }
    }
}

struct DBRowView: View {
    @Binding var row: DBRow
    let compact: () -> Void

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "cylinder.split.1x2").font(.system(size: 20)).foregroundStyle(row.tool.tint)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(row.tool.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                        Text(row.label).font(.system(size: 13, weight: .semibold))
                    }
                    Text(abbreviate(row.path)).font(Theme.mono).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.middle)
                    if let r = row.result {
                        Text(r).font(.system(size: 12)).foregroundStyle(Risk.safe.color)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(row.stats.map { ($0.fileBytes + $0.walBytes).bytes } ?? "—")
                        .font(.system(size: 13, design: .monospaced))
                    Text("可收回 " + (row.stats.map { $0.reclaimable.bytes } ?? "—"))
                        .font(.system(size: 11.5)).foregroundStyle(Risk.compact.color)
                }
                Group {
                    if row.busy {
                        ProgressView().controlSize(.small).frame(width: 96)
                    } else if row.running {
                        Text("请先退出 \(row.tool.name)").font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Risk.history.color).frame(width: 96)
                    } else {
                        Button("压缩", action: compact).buttonStyle(GhostButtonStyle()).frame(width: 96)
                    }
                }
            }
        }
    }
}
