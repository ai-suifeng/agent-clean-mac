import Foundation

public struct Finding: Identifiable, Sendable, Hashable {
    public var id: String { rule.id }
    public let toolId: String
    public let rule: RuleDef
    /// Absolute paths this finding covers: whole matches, or individual files for file-level age filtering.
    public let entries: [String]
    public let bytes: Int64
    public let fileCount: Int

    public var risk: Risk { rule.risk }
}

public struct ToolReport: Identifiable, Sendable, Hashable {
    public var id: String { tool.id }
    public let tool: ToolDef
    public let appMissing: Bool
    public let findings: [Finding]
    public var bytes: Int64 { findings.reduce(0) { $0 + $1.bytes } }
}

public struct Scanner: Sendable {
    public let rules: RuleSet
    public let home: String
    public let maxAgeDays: Int
    public let now: Date
    public let appDirs: [String]

    public init(rules: RuleSet, home: String = NSHomeDirectory(), maxAgeDays: Int? = nil, now: Date = Date(), appDirs: [String]? = nil) {
        self.rules = rules
        self.home = home
        self.maxAgeDays = maxAgeDays ?? rules.defaults.historyMaxAgeDays
        self.now = now
        self.appDirs = appDirs ?? ["/Applications", home + "/Applications", "/Applications/Setapp"]
    }

    var cutoff: Date { now.addingTimeInterval(-Double(maxAgeDays) * 86_400) }

    public func isPresent(_ tool: ToolDef) -> Bool {
        (tool.detect.paths ?? []).contains { !Glob.expand($0, home: home).isEmpty }
    }

    public func isAppMissing(_ tool: ToolDef) -> Bool {
        guard tool.orphanWhenAppMissing == true, let apps = tool.detect.apps, !apps.isEmpty else { return false }
        return !apps.contains { app in appDirs.contains { FileManager.default.fileExists(atPath: $0 + "/" + app) } }
    }

    /// Directories that must never be removed whole, whatever a rule says.
    var guarded: Set<String> {
        Set(["", "/", "/Users", "/Applications", "/Library", "/System", "/private", home] +
            ["Library", "Library/Application Support", "Library/Caches", "Library/Logs", "Library/Preferences",
             ".config", ".local", ".local/share", ".cache", ".npm", ".bun", "Documents", "Desktop", "Downloads"]
            .map { home + "/" + $0 })
    }

    public func scan(_ tool: ToolDef) -> ToolReport? {
        guard isPresent(tool) else { return nil }
        let appMissing = isAppMissing(tool)
        let hasOrphanRule = tool.rules.contains { $0.onlyWhen == "appMissing" }
        let active = tool.rules.filter { r in
            if appMissing && hasOrphanRule { return r.onlyWhen == "appMissing" }
            return r.onlyWhen != "appMissing"
        }
        let protected = active.filter { $0.risk == .protected }
            .flatMap { $0.paths.flatMap { Glob.expand($0, home: home) } }

        var claimed: [String] = []
        var findings: [Finding] = []
        for rule in active {
            let matches = rule.paths.flatMap { Glob.expand($0, home: home) }
            if rule.risk == .protected {
                let us = matches.map(DiskUsage.measure)
                let bytes = us.reduce(0) { $0 + $1.bytes }
                if bytes > 0 { findings.append(Finding(toolId: tool.id, rule: rule, entries: matches, bytes: bytes, fileCount: us.reduce(0) { $0 + $1.files })) }
                continue
            }
            let candidates = matches.filter { m in
                !guarded.contains(m) && m.isWithin(home)
                    && !claimed.contains { m.isWithin($0) }
                    && !protected.contains { m.isWithin($0) || $0.isWithin(m) }
            }
            var entries: [String] = []
            var bytes: Int64 = 0
            var files = 0
            for c in candidates {
                if rule.action == .ageFilter && rule.ageUnit != "entry" {
                    var seen = Set<[UInt64]>()
                    DiskUsage.walkFiles(c) { path, st in
                        guard st.mtime < cutoff, !protected.contains(where: { path.isWithin($0) }) else { return }
                        entries.append(path)
                        files += 1
                        if st.st_nlink > 1, !seen.insert([UInt64(st.st_dev), st.st_ino]).inserted { return }
                        bytes += Int64(st.st_blocks) * 512
                    }
                } else {
                    let u = DiskUsage.measure(c)
                    if rule.action == .ageFilter, let newest = u.newest, newest >= cutoff { continue }
                    entries.append(c)
                    bytes += u.bytes
                    files += u.files
                }
            }
            claimed += candidates
            if !entries.isEmpty && bytes > 0 {
                findings.append(Finding(toolId: tool.id, rule: rule, entries: entries, bytes: bytes, fileCount: files))
            }
        }
        return ToolReport(tool: tool, appMissing: appMissing, findings: findings)
    }

    /// Scans every tool concurrently and yields each report as soon as it is ready.
    public func scanAll() -> AsyncStream<ToolReport> {
        AsyncStream { cont in
            let task = Task.detached {
                await withTaskGroup(of: ToolReport?.self) { group in
                    for tool in rules.tools { group.addTask { scan(tool) } }
                    for await r in group { if let r { cont.yield(r) } }
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
