import Foundation
import SQLite3

public enum SessionFormat: String, Sendable, Codable {
    case claude, codex

    public var toolName: String { self == .claude ? "Claude Code" : "Codex" }
}

public struct SessionInfo: Identifiable, Sendable, Hashable {
    public var id: String { path }
    public let path: String
    public let format: SessionFormat
    public let title: String
    public let project: String
    public let date: Date
    public let bytes: Int64

    public var projectName: String { project.isEmpty ? "未知项目" : (project as NSString).lastPathComponent }
}

public enum SessionError: LocalizedError {
    case needsZstd
    public var errorDescription: String? { "这些 Codex 会话是 zstd 压缩格式，导出前需要先安装 zstd（brew install zstd）。" }
}

public enum Sessions {
    // MARK: Discovery

    public static func discover(home: String = NSHomeDirectory()) -> [SessionInfo] {
        let titles = codexTitles(home: home)
        let meta = codexThreads(home: home)
        let claude = Glob.expand("~/.claude/projects/*/*.jsonl", home: home).compactMap { info($0, .claude, titles: titles) }
        let codex = ["~/.codex/sessions/**/", "~/.codex/archived_sessions/**/"]
            .flatMap { dir in ["*.jsonl", "*.jsonl.zst"].flatMap { Glob.expand(dir + $0, home: home) } }
            .compactMap { info($0, .codex, titles: titles, meta: meta) }
        return (claude + codex).sorted { $0.date > $1.date }
    }

    /// Codex keeps thread names in session_index.jsonl, keyed by session id.
    static func codexTitles(home: String) -> [String: String] {
        var out: [String: String] = [:]
        forEachLine(home + "/.codex/session_index.jsonl") { o in
            if let id = o["id"] as? String, let name = o["thread_name"] as? String { out[id] = name }
            return true
        }
        return out
    }

    /// Codex's own thread table (state_N.sqlite) knows each thread's folder and title,
    /// which spares decompressing every archived rollout.
    static func codexThreads(home: String) -> [String: (title: String, cwd: String)] {
        guard let db = Glob.expand("~/.codex/state_*.sqlite", home: home).sorted().last else { return [:] }
        var h: OpaquePointer?
        defer { sqlite3_close(h) }
        guard sqlite3_open_v2(db, &h, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [:] }
        var out: [String: (String, String)] = [:]
        for sql in ["SELECT id, cwd, COALESCE(NULLIF(name, ''), NULLIF(title, ''), first_user_message, '') FROM threads",
                    "SELECT id, cwd, title FROM threads"] {
            var st: OpaquePointer?
            defer { sqlite3_finalize(st) }
            guard sqlite3_prepare_v2(h, sql, -1, &st, nil) == SQLITE_OK else { continue }
            while sqlite3_step(st) == SQLITE_ROW {
                func col(_ i: Int32) -> String { sqlite3_column_text(st, i).map { String(cString: $0) } ?? "" }
                out[col(0)] = (col(2), col(1))
            }
            return out
        }
        return out
    }

    public static func info(_ path: String, _ format: SessionFormat, titles: [String: String] = [:],
                            meta: [String: (title: String, cwd: String)] = [:]) -> SessionInfo? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        if format == .codex, let m = meta[codexId(path)] {
            let t = titles[codexId(path)] ?? m.title
            return SessionInfo(path: path, format: format, title: clean(t), project: m.cwd, date: st.mtime, bytes: Int64(st.st_blocks) * 512)
        }
        var title = "", firstPrompt = "", project = ""
        switch format {
        case .claude:
            // Most lines are large tool output; only parse the few that can carry what we need.
            let aiTitle = Data(#""ai-title""#.utf8), cwdKey = Data(#""cwd""#.utf8), userKey = Data(#""type":"user""#.utf8)
            forEachRawLine(path) { line in
                let wanted = line.range(of: aiTitle) != nil
                    || (project.isEmpty && line.range(of: cwdKey) != nil)
                    || (firstPrompt.isEmpty && line.range(of: userKey) != nil)
                guard wanted, let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return true }
                if o["type"] as? String == "ai-title", let t = o["aiTitle"] as? String { title = t }
                if project.isEmpty, let cwd = o["cwd"] as? String { project = cwd }
                if firstPrompt.isEmpty, o["type"] as? String == "user", o["isMeta"] as? Bool != true,
                   let msg = o["message"] as? [String: Any] { firstPrompt = claudeTexts(msg["content"]).first ?? "" }
                return true
            }
        case .codex:
            var budget = 400
            forEachLine(path) { o in
                budget -= 1
                let p = (o["payload"] as? [String: Any]) ?? o
                if o["type"] as? String == "session_meta" {
                    if let cwd = p["cwd"] as? String { project = cwd }
                    if let id = p["id"] as? String, let t = titles[id] { title = t }
                }
                if title.isEmpty, let t = titles[codexId(path)] { title = t }
                if firstPrompt.isEmpty, p["type"] as? String == "message", p["role"] as? String == "user" {
                    firstPrompt = codexTexts(p["content"]).first ?? ""
                }
                return budget > 0 && (title.isEmpty || project.isEmpty) && firstPrompt.isEmpty
            }
        }
        if title.isEmpty { title = firstPrompt }
        return SessionInfo(path: path, format: format, title: clean(title),
                           project: project, date: st.mtime, bytes: Int64(st.st_blocks) * 512)
    }

    static func clean(_ title: String) -> String {
        var t = title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if t.count > 80 { t = String(t.prefix(80)) + "…" }
        return t.isEmpty ? "（无标题）" : t
    }

    // MARK: Markdown

    public static func markdown(_ s: SessionInfo) -> String {
        var out = "# \(s.title)\n\n"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        out += "- 工具：\(s.format.toolName)\n- 项目：\(s.project.isEmpty ? "未知" : s.project)\n- 最后更新：\(df.string(from: s.date))\n- 原始文件：`\(s.path)`\n\n---\n"
        var lastRole = ""
        var tool: (name: String, count: Int)?
        func flushTool() {
            guard let t = tool else { return }
            out += "> 工具调用：`\(t.name)`" + (t.count > 1 ? " × \(t.count)" : "") + "\n\n"
            tool = nil
        }
        func heading(_ role: String) {
            if role != lastRole { flushTool(); out += "\n## \(role == "user" ? "用户" : "助手")\n\n"; lastRole = role }
        }
        func emit(_ role: String, _ text: String) {
            heading(role)
            flushTool()
            out += text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        }
        // Runs of the same tool collapse into one line with a count.
        func emitTool(_ name: String) {
            heading("assistant")
            if tool?.name == name { tool!.count += 1 } else { flushTool(); tool = (name, 1) }
        }
        forEachLine(s.path) { o in
            switch s.format {
            case .claude:
                guard let type = o["type"] as? String, type == "user" || type == "assistant",
                      o["isMeta"] as? Bool != true, o["isSidechain"] as? Bool != true,
                      let msg = o["message"] as? [String: Any] else { return true }
                for t in claudeTexts(msg["content"]) { emit(type, t) }
                if let blocks = msg["content"] as? [[String: Any]] {
                    for b in blocks where b["type"] as? String == "tool_use" { emitTool(b["name"] as? String ?? "?") }
                }
            case .codex:
                let p = (o["payload"] as? [String: Any]) ?? o
                switch p["type"] as? String {
                case "message":
                    guard let role = p["role"] as? String, role == "user" || role == "assistant" else { break }
                    for t in codexTexts(p["content"]) { emit(role, t) }
                case "function_call", "custom_tool_call", "local_shell_call":
                    emitTool(p["name"] as? String ?? "shell")
                default: break
                }
            }
            return true
        }
        flushTool()
        return out
    }

    /// Writes each session to `<dir>/<tool>/<project>/<date> <title>.md` and returns the files written.
    public static func export(_ sessions: [SessionInfo], to dir: URL) throws -> [URL] {
        let fm = FileManager.default
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HHmm"
        var written: [URL] = []
        for s in sessions {
            guard canRead(s) else { throw SessionError.needsZstd }
            let folder = dir.appendingPathComponent(s.format.toolName).appendingPathComponent(safeName(s.projectName))
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var name = "\(df.string(from: s.date)) \(safeName(String(s.title.prefix(50))))"
            var url = folder.appendingPathComponent(name + ".md")
            var n = 2
            while fm.fileExists(atPath: url.path) { url = folder.appendingPathComponent("\(name) \(n).md"); n += 1 }
            name = url.lastPathComponent
            try markdown(s).write(to: url, atomically: true, encoding: .utf8)
            written.append(url)
        }
        return written
    }

    static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        return s.components(separatedBy: bad).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: Parsing helpers

    /// `rollout-<time>-<uuid>.jsonl[.zst]` → uuid
    static func codexId(_ path: String) -> String {
        var name = (path as NSString).lastPathComponent
        for ext in [".zst", ".jsonl"] where name.hasSuffix(ext) { name.removeLast(ext.count) }
        return String(name.suffix(36))
    }

    /// Codex compresses old rollouts with zstd; reading them needs the `zstd` tool.
    public static var zstdPath: String? {
        ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func canRead(_ s: SessionInfo) -> Bool { !s.path.hasSuffix(".zst") || zstdPath != nil }

    /// Text the person or the model actually wrote, without injected context blocks.
    static func isNoise(_ t: String) -> Bool {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty || s.hasPrefix("<") || s.hasPrefix("# AGENTS.md") || s.hasPrefix("Caveat:")
    }

    static func claudeTexts(_ content: Any?) -> [String] {
        if let s = content as? String { return isNoise(s) ? [] : [s] }
        guard let blocks = content as? [[String: Any]] else { return [] }
        return blocks.compactMap { b in
            guard b["type"] as? String == "text", let t = b["text"] as? String, !isNoise(t) else { return nil }
            return t
        }
    }

    static func codexTexts(_ content: Any?) -> [String] {
        guard let blocks = content as? [[String: Any]] else { return [] }
        return blocks.compactMap { b in
            guard let t = b["text"] as? String, !isNoise(t) else { return nil }
            return t
        }
    }

    /// Calls `body` with each JSON object line until it returns false.
    static func forEachLine(_ path: String, _ body: ([String: Any]) -> Bool) {
        forEachRawLine(path) { line in
            guard let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return true }
            return body(o)
        }
    }

    /// Calls `body` with each non-empty raw line until it returns false. Reads `.zst` through the zstd tool.
    static func forEachRawLine(_ path: String, _ body: (Data) -> Bool) {
        var proc: Process?
        let fh: FileHandle
        if path.hasSuffix(".zst") {
            guard let zstd = zstdPath else { return }
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: zstd)
            p.arguments = ["-dcq", path]
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            proc = p
            fh = pipe.fileHandleForReading
        } else {
            guard let f = FileHandle(forReadingAtPath: path) else { return }
            fh = f
        }
        defer {
            try? fh.close()
            if let proc, proc.isRunning { proc.terminate() }
            proc?.waitUntilExit()
        }
        var buffer = Data()
        func handle(_ line: Data) -> Bool { line.isEmpty ? true : body(line) }
        while let chunk = try? fh.read(upToCount: 1 << 20), !chunk.isEmpty {
            buffer.append(chunk)
            var start = buffer.startIndex
            while let nl = buffer[start...].firstIndex(of: 0x0A) {
                if !handle(buffer[start..<nl]) { return }
                start = buffer.index(after: nl)
            }
            buffer = Data(buffer[start...])
        }
        _ = handle(buffer)
    }
}
