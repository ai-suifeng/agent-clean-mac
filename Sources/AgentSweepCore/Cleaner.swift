import Foundation

public struct Move: Codable, Sendable, Hashable {
    public let from: String
    public let to: String
}

public struct CleanItemRecord: Codable, Sendable, Hashable {
    public let ruleId: String
    public let toolName: String
    public let label: String
    public let bytes: Int64
    public var moves: [Move]
    public var failures: [String]

    public init(ruleId: String, toolName: String, label: String, bytes: Int64, moves: [Move], failures: [String]) {
        self.ruleId = ruleId
        self.toolName = toolName
        self.label = label
        self.bytes = bytes
        self.moves = moves
        self.failures = failures
    }
}

public struct CleanRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let date: Date
    public var items: [CleanItemRecord]
    public var restored: Bool = false

    public init(id: UUID, date: Date, items: [CleanItemRecord], restored: Bool = false) {
        self.id = id
        self.date = date
        self.items = items
        self.restored = restored
    }

    public var freedBytes: Int64 { items.filter { $0.failures.isEmpty }.reduce(0) { $0 + $1.bytes } }
    public var moveCount: Int { items.reduce(0) { $0 + $1.moves.count } }
}

public struct CleanJob: Sendable {
    public let finding: Finding
    public let toolName: String
    public init(finding: Finding, toolName: String) { self.finding = finding; self.toolName = toolName }
}

public enum Cleaner {
    /// Moves every entry to the Trash and remembers where it came from.
    /// Only removable risks under the home folder are touched.
    public static func trash(_ jobs: [CleanJob], home: String = NSHomeDirectory(), progress: (Double) -> Void = { _ in }) -> CleanRecord {
        let fm = FileManager.default
        let total = max(1, jobs.reduce(0) { $0 + $1.finding.entries.count })
        var done = 0
        var items: [CleanItemRecord] = []
        for job in jobs {
            let f = job.finding
            var rec = CleanItemRecord(ruleId: f.rule.id, toolName: job.toolName, label: f.rule.label, bytes: f.bytes, moves: [], failures: [])
            guard f.risk.isRemovable else {
                rec.failures.append("受保护的条目不会被删除")
                items.append(rec)
                continue
            }
            for path in f.entries {
                defer { done += 1; progress(Double(done) / Double(total)) }
                guard path.isWithin(home), path != home else { rec.failures.append(path); continue }
                var out: NSURL?
                do {
                    try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &out)
                    if let out = out as URL? { rec.moves.append(Move(from: path, to: out.path)) }
                } catch {
                    // Already gone counts as cleaned.
                    if fm.fileExists(atPath: path) { rec.failures.append(path) }
                }
            }
            items.append(rec)
        }
        return CleanRecord(id: UUID(), date: Date(), items: items)
    }

    /// Trashes loose files picked by hand (for example sessions), recorded as one history item.
    public static func trashFiles(_ paths: [String], label: String, toolName: String, bytes: Int64, home: String = NSHomeDirectory()) -> CleanRecord {
        let rule = RuleDef(id: "manual-\(UUID().uuidString.prefix(8))", label: label, paths: [], risk: .history, action: .trash,
                           explain: "", export: nil, onlyWhen: nil, ageUnit: nil)
        let f = Finding(toolId: "", rule: rule, entries: paths, bytes: bytes, fileCount: paths.count)
        return trash([CleanJob(finding: f, toolName: toolName)], home: home)
    }

    public struct RestoreResult: Sendable {
        public var restored = 0
        /// Items still in the Trash that could not be moved back (macOS guards the Trash without Full Disk Access).
        public var blocked: [String] = []
        /// Items that are gone from the Trash (it was emptied) or whose original place is taken.
        public var missing = 0
    }

    /// Moves trashed items back to where they were.
    public static func restore(_ record: CleanRecord) -> RestoreResult {
        let fm = FileManager.default
        var r = RestoreResult()
        for item in record.items {
            for m in item.moves {
                let inTrash = fm.fileExists(atPath: m.to), atHome = fm.fileExists(atPath: m.from)
                if atHome && !inTrash { r.restored += 1; continue } // already put back
                guard inTrash, !atHome else { r.missing += 1; continue }
                do {
                    try fm.createDirectory(atPath: (m.from as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                    try fm.moveItem(atPath: m.to, toPath: m.from)
                    r.restored += 1
                } catch {
                    r.blocked.append(m.to)
                }
            }
        }
        return r
    }
}

/// Clean records kept as JSON files in Application Support.
public struct HistoryStore: Sendable {
    public let dir: URL

    public init(dir: URL? = nil) {
        self.dir = dir ?? AppPaths.support.appendingPathComponent("history", isDirectory: true)
    }

    public func save(_ r: CleanRecord) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        try enc.encode(r).write(to: dir.appendingPathComponent("\(r.id.uuidString).json"), options: .atomic)
    }

    public func load() -> [CleanRecord] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? dec.decode(CleanRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }
}

public enum AppPaths {
    public static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentSweep", isDirectory: true)
    }
}
