import Foundation

extension RuleSet {
    /// Folder for extra rule files. Each `*.json` holds `{"tools": [...]}`; a tool with the same id replaces the bundled one.
    public static var userRulesDir: URL { AppPaths.support.appendingPathComponent("rules.d", isDirectory: true) }

    /// Bundled rules plus any rule files the user dropped into `rules.d`.
    public static func load(userDir: URL = userRulesDir) -> (rules: RuleSet, errors: [String]) {
        var base = (try? bundled()) ?? RuleSet(version: 0, updated: "", defaults: .init(historyMaxAgeDays: 30), tools: [])
        var errors: [String] = []
        let files = ((try? FileManager.default.contentsOfDirectory(at: userDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        struct Extra: Decodable { let tools: [ToolDef] }
        for f in files {
            do {
                let extra = try JSONDecoder().decode(Extra.self, from: Data(contentsOf: f))
                var tools = base.tools
                for t in extra.tools {
                    if let i = tools.firstIndex(where: { $0.id == t.id }) { tools[i] = t } else { tools.append(t) }
                }
                base = RuleSet(version: base.version, updated: base.updated, defaults: base.defaults, tools: tools)
            } catch {
                errors.append("\(f.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return (base, errors)
    }
}

/// A folder that looks like it belongs to an AI coding tool the rules do not cover yet. Only ever shown, never cleaned.
public struct UnknownAgent: Identifiable, Sendable, Hashable {
    public var id: String { path }
    public let path: String
    public let bytes: Int64
    public let reason: String
}

public enum Discovery {
    /// Names that usually mean an AI coding tool.
    static let keywords = ["agent", "claude", "codex", "copilot", "cursor", "kimi", "moonshot", "qwen", "deepseek", "minimax",
                           "zcode", "zhipu", "glm", "gemini", "antigravity", "kiro", "trae", "windsurf", "codeium", "cline",
                           "roo", "aider", "continue", "opencode", "goose", "augment", "tabnine", "amp", "openai", "anthropic",
                           "llm", "gpt", "ollama", "lmstudio", "warp", "crush", "factory", "qoder", "codebuddy", "lingma",
                           "tongyi", "doubao", "marscode", "comate", "iflow", "harness"]
    /// Files and folders agent tools typically keep at the top of their data folder.
    static let markers = ["sessions", "skills", "mcp.json", "AGENTS.md", "projects", "conversations", "agents", "checkpoints"]

    public static func findUnknown(rules: RuleSet, home: String = NSHomeDirectory()) -> [UnknownAgent] {
        let known = rules.tools.flatMap { t in
            (t.detect.paths ?? []) + t.rules.flatMap(\.paths)
        }.flatMap { Glob.expand($0, home: home) }
        let fm = FileManager.default
        var out: [UnknownAgent] = []
        let roots: [(dir: String, hiddenOnly: Bool)] = [(home, true), (home + "/Library/Application Support", false)]
        for (dir, hiddenOnly) in roots {
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
                if hiddenOnly && !name.hasPrefix(".") { continue }
                let path = dir + "/" + name
                guard Glob.isDir(path) else { continue }
                // Covered when a known path sits inside it or it sits inside a known path.
                if known.contains(where: { $0.isWithin(path) || path.isWithin($0) }) { continue }
                let lower = name.lowercased()
                // Short words need word boundaries ("amp" in "camp" is not a tool); longer ones are distinctive enough.
                let word = keywords.first { k in
                    k.count >= 5 ? lower.contains(k)
                        : lower.range(of: "(^|[^a-z])\(k)([^a-z]|$)", options: .regularExpression) != nil
                }
                let children = Set((try? fm.contentsOfDirectory(atPath: path)) ?? [])
                let marks = markers.filter(children.contains)
                guard word != nil || marks.count >= 2 else { continue }
                let bytes = DiskUsage.measure(path).bytes
                guard bytes >= 1_000_000 else { continue }
                let reason = word.map { "名字里有「\($0)」" } ?? "里面有 \(marks.joined(separator: "、"))"
                out.append(UnknownAgent(path: path, bytes: bytes, reason: reason))
            }
        }
        return out.sorted { $0.bytes > $1.bytes }
    }
}
