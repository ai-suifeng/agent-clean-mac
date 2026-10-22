import AppKit
import AgentSweepCore
import Observation
import SwiftUI

enum Phase { case idle, scanning, results, cleaning, done }

enum Section: String, CaseIterable, Identifiable {
    case clean, sessions, compact, history, rules
    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: "智能清理"
        case .sessions: "会话历史"
        case .compact: "数据库压缩"
        case .history: "清理记录"
        case .rules: "规则库"
        }
    }

    var icon: String {
        switch self {
        case .clean: "scope"
        case .sessions: "bubble.left.and.text.bubble.right"
        case .compact: "cylinder.split.1x2"
        case .history: "clock.arrow.circlepath"
        case .rules: "list.bullet.rectangle"
        }
    }
}

struct LogLine: Identifiable {
    let id = UUID()
    let path: String
    let size: String
}

@MainActor @Observable
final class AppModel {
    var section: Section = .clean
    var phase: Phase = .idle
    let rules: RuleSet
    var reports: [String: ToolReport] = [:]
    var log: [LogLine] = []
    var selected: Set<String> = []
    var cleaned: Set<String> = []
    var hovered: String?
    var lastRecord: CleanRecord?
    var toast: String?
    var confirmClean = false
    var history: [CleanRecord] = []
    var ruleErrors: [String] = []

    @ObservationIgnored let engine = StageEngine()
    @ObservationIgnored private var pending: [ToolReport] = []
    @ObservationIgnored private var scanFinished = false
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored let historyStore = HistoryStore()
    @ObservationIgnored let home = appHome

    init() {
        let loaded = RuleSet.load()
        rules = loaded.rules
        ruleErrors = loaded.errors
        history = historyStore.load()
        engine.reset(toolCount: rules.tools.count)
    }

    // MARK: Derived

    var tools: [ToolDef] { rules.tools }

    /// Revealed findings in tool order, then risk order: the order the ring and list use.
    var findings: [Finding] {
        tools.compactMap { reports[$0.id] }.flatMap { r in
            r.findings.sorted { Risk.order.firstIndex(of: $0.risk)! < Risk.order.firstIndex(of: $1.risk)! }
        }
    }

    func tool(_ id: String) -> ToolDef? { tools.first { $0.id == id } }
    var foundBytes: Int64 { findings.reduce(0) { $0 + $1.bytes } }
    var removableBytes: Int64 { findings.filter { $0.risk.isRemovable }.reduce(0) { $0 + $1.bytes } }
    var compactBytes: Int64 { findings.filter { $0.risk == .compact }.reduce(0) { $0 + $1.bytes } }
    var selectedFindings: [Finding] { findings.filter { selected.contains($0.id) && !cleaned.contains($0.id) } }
    var selectedBytes: Int64 { selectedFindings.reduce(0) { $0 + $1.bytes } }

    var runningSelectedTools: [String] {
        let paths = ProcessDetector.executablePaths()
        return Set(selectedFindings.map(\.toolId)).compactMap { tool($0) }
            .filter { ProcessDetector.isRunning($0, paths: paths) }.map(\.name).sorted()
    }

    // MARK: Scan

    func startScan() {
        reports = [:]; log = []; selected = []; cleaned = []; hovered = nil
        pending = []; scanFinished = false
        engine.reset(toolCount: tools.count)
        phase = .scanning
        let scanner = AgentSweepCore.Scanner(rules: rules, home: home)
        Task.detached { [weak self] in
            for await r in scanner.scanAll() { await self?.enqueue(r) }
            await self?.finishScan()
        }
        Task { await revealLoop() }
    }

    private func enqueue(_ r: ToolReport) { pending.append(r) }
    private func finishScan() { scanFinished = true }

    /// Reveals results at a readable pace even when the scanner finishes several tools at once.
    private func revealLoop() async {
        while phase == .scanning {
            if !pending.isEmpty {
                reveal(pending.removeFirst())
                try? await Task.sleep(for: .milliseconds(engine.reduceMotion ? 60 : 480))
            } else if scanFinished {
                try? await Task.sleep(for: .milliseconds(550))
                toResults()
                return
            } else {
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func reveal(_ r: ToolReport) {
        reports[r.id] = r
        guard let i = tools.firstIndex(where: { $0.id == r.id }) else { return }
        engine.reveal(index: i, id: r.id, bytes: r.bytes, color: r.tool.tint)
        for f in r.findings.prefix(6) {
            log.insert(LogLine(path: "\(r.tool.name) · \(f.rule.label)", size: f.bytes.bytes), at: 0)
        }
    }

    private func toResults() {
        selected = Set(findings.filter { $0.risk.isRemovable }.map(\.id))
        engine.beginResults(target: Double(selectedBytes))
        withAnimation(.smooth) { phase = .results }
        #if DEBUG
        // Debug builds only: play the clean animation against a --home test folder (simulated, see clean()).
        if home != NSHomeDirectory(), CommandLine.arguments.contains("--demo-clean") {
            Task { try? await Task.sleep(for: .seconds(2.5)); clean() }
        }
        #endif
    }

    func toggle(_ id: String) {
        guard phase == .results, let f = findings.first(where: { $0.id == id }), f.risk.isRemovable else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        engine.target = Double(selectedBytes)
    }

    /// Removable, not yet cleaned findings in one risk group.
    func groupIDs(_ risk: Risk) -> [String] {
        guard risk.isRemovable else { return [] }
        return findings.filter { $0.risk == risk && !cleaned.contains($0.id) }.map(\.id)
    }

    /// Ticks every item in the group, or clears them all when every item is already ticked.
    func toggleGroup(_ risk: Risk) {
        guard phase == .results else { return }
        let ids = groupIDs(risk)
        if ids.allSatisfy(selected.contains) { selected.subtract(ids) } else { selected.formUnion(ids) }
        engine.target = Double(selectedBytes)
    }

    func invertGroup(_ risk: Risk) {
        guard phase == .results else { return }
        for id in groupIDs(risk) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        }
        engine.target = Double(selectedBytes)
    }

    // MARK: Clean

    func clean() {
        let picked = selectedFindings
        guard !picked.isEmpty else { return }
        let jobs = picked.map { CleanJob(finding: $0, toolName: tool($0.toolId)?.name ?? $0.toolId) }
        let bytes = selectedBytes
        hovered = nil
        engine.beginClean(ids: picked.map(\.id), bytes: Double(bytes))
        withAnimation(.smooth) { phase = .cleaning }
        let started = Date()
        let home = home
        #if DEBUG
        // --demo-clean only plays the animation; nothing is moved and no record is kept.
        let simulate = CommandLine.arguments.contains("--demo-clean")
        #else
        let simulate = false
        #endif
        Task {
            let record: CleanRecord
            if simulate {
                record = CleanRecord(id: UUID(), date: Date(), items: jobs.map {
                    CleanItemRecord(ruleId: $0.finding.id, toolName: $0.toolName, label: $0.finding.rule.label,
                                    bytes: $0.finding.bytes, moves: [], failures: [])
                })
            } else {
                record = await Task.detached { Cleaner.trash(jobs, home: home) }.value
                try? historyStore.save(record)
            }
            let wait = engine.cleanDuration - Date().timeIntervalSince(started)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            finishClean(record)
        }
    }

    private func finishClean(_ record: CleanRecord) {
        lastRecord = record
        cleaned.formUnion(record.items.filter { $0.failures.isEmpty }.map(\.ruleId))
        history = historyStore.load()
        engine.finishClean(freed: Double(record.freedBytes))
        withAnimation(.smooth) { phase = .done }
        let failed = record.items.reduce(0) { $0 + $1.failures.count }
        if failed > 0 { show("\(failed) 个文件没能移走，可能正在被使用。退出对应工具后再试一次。") }
    }

    func reset() {
        engine.reset(toolCount: tools.count)
        reports = [:]; log = []; selected = []; cleaned = []; lastRecord = nil
        withAnimation(.smooth) { phase = .idle }
    }

    // MARK: Export

    func export(_ finding: Finding) {
        guard let dir = chooseExportFolder() else { return }
        let entries = finding.entries
        let format: SessionFormat = finding.rule.export == "claude" ? .claude : .codex
        show("正在导出 \(entries.count) 个会话…")
        Task {
            do {
                let files = try await Task.detached {
                    let infos = entries.flatMap { e -> [String] in
                        e.hasSuffix(".jsonl") || e.hasSuffix(".zst") ? [e] : []
                    }.compactMap { Sessions.info($0, format) }
                    return try Sessions.export(infos, to: dir)
                }.value
                show("已导出 \(files.count) 个会话到 \(abbreviate(dir.path))")
                NSWorkspace.shared.activateFileViewerSelecting([dir])
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    func chooseExportFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "导出到这里"
        panel.message = "选择会话导出的位置，每个会话会保存成一个 Markdown 文件"
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: History

    /// Trash paths that macOS would not let us move back; the history page explains what to do.
    var restoreBlocked: [String] = []

    func restore(_ record: CleanRecord) {
        let r = Cleaner.restore(record)
        if r.blocked.isEmpty {
            var updated = record
            updated.restored = true
            try? historyStore.save(updated)
            history = historyStore.load()
        }
        restoreBlocked = r.blocked
        if r.blocked.isEmpty {
            show(r.missing == 0 ? "已恢复 \(r.restored) 项" : "已恢复 \(r.restored) 项，\(r.missing) 项已经不在废纸篓里")
        }
    }

    func showBlockedInTrash() {
        NSWorkspace.shared.activateFileViewerSelecting(restoreBlocked.map { URL(fileURLWithPath: $0) })
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Toast

    func show(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { toast = nil }
        }
    }
}

/// Folder treated as the home folder. `--home <dir>` points it at a test folder (screenshots, development).
let appHome: String = {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--home"), i + 1 < args.count { return args[i + 1] }
    return NSHomeDirectory()
}()

func abbreviate(_ path: String) -> String {
    let home = appHome
    var p = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    p = p.replacingOccurrences(of: "~/Library/Application Support/", with: "…/")
    return p
}
