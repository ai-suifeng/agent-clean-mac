import XCTest
@testable import AgentSweepCore

final class CoreTests: XCTestCase {
    var home: String!

    override func setUpWithError() throws {
        home = (NSTemporaryDirectory() as NSString).appendingPathComponent("agentsweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    @discardableResult
    func file(_ rel: String, bytes: Int = 5000, ageDays: Double = 0) -> String { file(rel, ageDays, nil, bytes: bytes) }

    @discardableResult
    func file(_ rel: String, _ ageDays: Double, _ text: String?, bytes: Int = 5000) -> String {
        let p = home + "/" + rel
        try! FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: p, contents: text.map { Data($0.utf8) } ?? Data(count: bytes))
        let d = Date().addingTimeInterval(-ageDays * 86_400)
        try! FileManager.default.setAttributes([.modificationDate: d], ofItemAtPath: p)
        return p
    }

    @discardableResult
    func text(_ rel: String, _ content: String) -> String { file(rel, 0, content) }

    func rules(_ tools: [ToolDef]) -> RuleSet {
        RuleSet(version: 1, updated: "", defaults: .init(historyMaxAgeDays: 30), tools: tools)
    }

    func rule(_ id: String, _ paths: [String], _ risk: Risk, _ action: RuleAction, unit: String? = nil, onlyWhen: String? = nil) -> RuleDef {
        RuleDef(id: id, label: id, paths: paths, risk: risk, action: action, explain: "", export: nil, onlyWhen: onlyWhen, ageUnit: unit)
    }

    func tool(_ id: String, _ rules: [RuleDef], detect: [String], apps: [String]? = nil) -> ToolDef {
        ToolDef(id: id, name: id, color: "#fff", detect: DetectDef(paths: detect, apps: apps, processes: nil),
                shared: nil, orphanWhenAppMissing: apps != nil, rules: rules)
    }

    func testBundledRulesDecode() throws {
        let rs = try RuleSet.bundled()
        XCTAssertGreaterThan(rs.tools.count, 8)
        let ids = rs.tools.flatMap { $0.rules.map(\.id) }
        XCTAssertEqual(ids.count, Set(ids).count, "rule ids must be unique")
    }

    func testGlobBracesStarsAndDoubleStar() {
        file("a/Cache/x"); file("a/GPUCache/y"); file("a/Other/z")
        file("s/2026/01/02/one.jsonl"); file("s/top.jsonl"); file("s/2026/note.txt")
        file(".hidden.tmp-1")
        XCTAssertEqual(Set(Glob.expand("~/a/{Cache,GPUCache,Missing}", home: home)), [home + "/a/Cache", home + "/a/GPUCache"])
        XCTAssertEqual(Set(Glob.expand("~/s/**/*.jsonl", home: home)), [home + "/s/2026/01/02/one.jsonl", home + "/s/top.jsonl"])
        XCTAssertEqual(Glob.expand("~/.hidden.tmp-*", home: home), [home + "/.hidden.tmp-1"])
    }

    func testProtectedPathsAreNeverIncluded() {
        file(".t/cache/a"); file(".t/settings.json"); file(".t/skills/s.md")
        let t = tool("t", [
            rule("p", ["~/.t/settings.json", "~/.t/skills"], .protected, .none),
            rule("all", ["~/.t", "~/.t/*"], .safe, .trash),
        ], detect: ["~/.t"])
        let r = Scanner(rules: rules([t]), home: home).scan(t)!
        let entries = r.findings.first { $0.rule.id == "all" }!.entries
        XCTAssertEqual(entries, [home + "/.t/cache"], "parent of protected and protected itself are skipped")
        XCTAssertEqual(r.findings.first { $0.risk == .protected }?.entries.count, 2)
    }

    func testGuardedDirectoriesAreNeverIncluded() {
        file(".cache/uv/x")
        let t = tool("t", [rule("bad", ["~", "~/.cache", "~/Library"], .safe, .trash)], detect: ["~/.cache"])
        XCTAssertTrue(Scanner(rules: rules([t]), home: home).scan(t)!.findings.isEmpty)
    }

    func testAgeFilterByFileAndByEntry() {
        file("s/old.jsonl", ageDays: 60); file("s/new.jsonl", ageDays: 2)
        file("w/oldproj/state", ageDays: 90); file("w/active/a", ageDays: 90); file("w/active/b", ageDays: 1)
        let t = tool("t", [
            rule("files", ["~/s"], .history, .ageFilter),
            rule("entries", ["~/w/*"], .history, .ageFilter, unit: "entry"),
        ], detect: ["~/s"])
        let r = Scanner(rules: rules([t]), home: home).scan(t)!
        XCTAssertEqual(r.findings.first { $0.rule.id == "files" }?.entries, [home + "/s/old.jsonl"])
        XCTAssertEqual(r.findings.first { $0.rule.id == "entries" }?.entries, [home + "/w/oldproj"])
    }

    func testOrphanRulesOnlyWhenAppMissing() {
        file(".x/cache/a"); file(".x/config")
        let rs = [rule("cache", ["~/.x/cache"], .safe, .trash), rule("orphan", ["~/.x"], .orphan, .trash, onlyWhen: "appMissing")]
        let missing = tool("x", rs, detect: ["~/.x"], apps: ["X.app"])
        let s = Scanner(rules: rules([missing]), home: home, appDirs: [home + "/Apps"])
        XCTAssertEqual(s.scan(missing)!.findings.map(\.rule.id), ["orphan"])

        file("Apps/X.app/Contents/Info.plist")
        XCTAssertEqual(s.scan(missing)!.findings.map(\.rule.id), ["cache"])
    }

    func testUndetectedToolIsSkipped() {
        let t = tool("none", [rule("a", ["~/.none"], .safe, .trash)], detect: ["~/.none"])
        XCTAssertNil(Scanner(rules: rules([t]), home: home).scan(t))
    }

    func testTrashAndRestore() throws {
        let p = file(".t/cache/blob")
        let t = tool("t", [rule("c", ["~/.t/cache"], .safe, .trash)], detect: ["~/.t"])
        let f = Scanner(rules: rules([t]), home: home).scan(t)!.findings[0]
        let rec = Cleaner.trash([CleanJob(finding: f, toolName: "t")], home: home)
        XCTAssertFalse(FileManager.default.fileExists(atPath: p))
        XCTAssertEqual(rec.moveCount, 1)
        XCTAssertEqual(Cleaner.restore(rec).restored, 1)
        XCTAssertEqual(Cleaner.restore(rec).restored, 1, "a second restore sees it is already back")
        XCTAssertTrue(FileManager.default.fileExists(atPath: p))
    }

    func testCleanerRefusesProtectedFindings() {
        let p = file(".t/auth.json")
        let f = Finding(toolId: "t", rule: rule("p", [], .protected, .none), entries: [p], bytes: 1, fileCount: 1)
        _ = Cleaner.trash([CleanJob(finding: f, toolName: "t")], home: home)
        XCTAssertTrue(FileManager.default.fileExists(atPath: p))
    }

    func testClaudeSessionMarkdown() {
        let lines = [
            #"{"type":"user","cwd":"/work/app","message":{"role":"user","content":"修一下登录页"}}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"meta stuff"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"好的，我来看看。"},{"type":"tool_use","name":"Read","input":{}}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"..."}]}}"#,
            #"{"type":"ai-title","aiTitle":"登录页修复"}"#,
        ]
        let p = text(".claude/projects/-work-app/s1.jsonl", lines.joined(separator: "\n"))
        let s = Sessions.info(p, .claude)!
        XCTAssertEqual(s.title, "登录页修复")
        XCTAssertEqual(s.projectName, "app")
        let md = Sessions.markdown(s)
        XCTAssertTrue(md.contains("## 用户\n\n修一下登录页"))
        XCTAssertTrue(md.contains("好的，我来看看。"))
        XCTAssertTrue(md.contains("> 工具调用：`Read` × 2"))
        XCTAssertFalse(md.contains("meta stuff"))
    }

    func testCodexSessionMarkdownAndIndexTitle() throws {
        text(".codex/session_index.jsonl", #"{"id":"abc","thread_name":"加搜索框"}"#)
        let lines = [
            #"{"type":"session_meta","payload":{"id":"abc","cwd":"/work/site"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"secret instructions"}]}}"#,
            ##"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions"}]}}"##,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"给首页加个搜索框"}]}}"#,
            #"{"type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{}"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"已经加好了。"}]}}"#,
        ]
        text(".codex/sessions/2026/10/01/rollout-1.jsonl", lines.joined(separator: "\n"))
        let all = Sessions.discover(home: home)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].title, "加搜索框")
        let md = Sessions.markdown(all[0])
        XCTAssertTrue(md.contains("给首页加个搜索框"))
        XCTAssertTrue(md.contains("已经加好了。"))
        XCTAssertFalse(md.contains("secret instructions"))
        XCTAssertFalse(md.contains("AGENTS.md"))

        let out = URL(fileURLWithPath: home + "/export")
        let files = try Sessions.export(all, to: out)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].path.contains("/Codex/site/"))
    }

    func testCompressedCodexSession() throws {
        guard let zstd = Sessions.zstdPath else { throw XCTSkip("zstd not installed") }
        let id = "019b44c9-bb0c-7ff1-8aff-d4d8682b924f"
        let plain = text("raw.jsonl", [
            #"{"type":"session_meta","payload":{"id":"\#(id)","cwd":"/work/old"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"老问题"}]}}"#,
        ].joined(separator: "\n"))
        let dest = home + "/.codex/sessions/2025/12/22/rollout-2025-12-22T14-40-29-\(id).jsonl.zst"
        try FileManager.default.createDirectory(atPath: (dest as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: zstd)
        p.arguments = ["-q", plain, "-o", dest]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(Sessions.codexId(dest), id)
        let s = try XCTUnwrap(Sessions.discover(home: home).first)
        XCTAssertEqual(s.projectName, "old")
        XCTAssertTrue(Sessions.markdown(s).contains("老问题"))
    }

    func testReadoutParts() {
        XCTAssertEqual(ByteFormat.parts(557_000).0 + ByteFormat.parts(557_000).1, "557KB")
        XCTAssertEqual(ByteFormat.parts(34_210_000_000).0, "34.2")
        XCTAssertEqual(ByteFormat.parts(250_000_000).1, "MB")
    }

    func testProcessMatching() {
        let t = ToolDef(id: "c", name: "Cursor", color: "", detect: DetectDef(paths: nil, apps: nil, processes: ["Cursor"]),
                        shared: nil, orphanWhenAppMissing: nil, rules: [])
        XCTAssertTrue(ProcessDetector.isRunning(t, paths: ["/Applications/Cursor.app/Contents/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper"]))
        XCTAssertFalse(ProcessDetector.isRunning(t, paths: ["/usr/bin/cursorless"]))
    }

    func testSQLiteStatsAndCompact() throws {
        let p = home + "/db.sqlite"
        var db: OpaquePointer?
        sqlite3_open(p, &db)
        sqlite3_exec(db, "CREATE TABLE t(x BLOB); WITH RECURSIVE c(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM c WHERE i<2000) INSERT INTO t SELECT randomblob(1000) FROM c; DELETE FROM t;", nil, nil, nil)
        sqlite3_close(db)
        let s = try SQLiteCompactor.stats(p)
        XCTAssertGreaterThan(s.reclaimable, 1_000_000)
        let r = try SQLiteCompactor.compact(p, backupDir: URL(fileURLWithPath: home + "/bk"))
        XCTAssertLessThan(r.after, r.before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.backup))
    }
}

import SQLite3

final class DiscoveryTests: XCTestCase {
    func testUserRulesAddAndReplaceTools() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try ##"{"tools":[{"id":"newtool","name":"New Tool","color":"#fff","detect":{"paths":["~/.newtool"]},"rules":[]},{"id":"kiro","name":"Kiro X","color":"#fff","detect":{"paths":[]},"rules":[]}]}"##
            .write(to: dir.appendingPathComponent("extra.json"), atomically: true, encoding: .utf8)
        try "not json".write(to: dir.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
        let (rules, errors) = RuleSet.load(userDir: dir)
        XCTAssertEqual(rules.tools.last?.id, "newtool")
        XCTAssertEqual(rules.tools.first { $0.id == "kiro" }?.name, "Kiro X")
        XCTAssertEqual(errors.count, 1)
    }

    func testFindsUncoveredAgentFolders() throws {
        let home = NSTemporaryDirectory() + "disc-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: home) }
        let fm = FileManager.default
        for (rel, size) in [(".newagent/sessions/a", 2_000_000), (".mystery/sessions/a", 2_000_000), (".mystery/skills/b", 10),
                            (".covered/x", 2_000_000), (".notes/x", 2_000_000), ("Library/Application Support/SuperCopilot/c", 2_000_000)] {
            let p = home + "/" + rel
            try fm.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: p, contents: Data(count: size))
        }
        let covered = ToolDef(id: "c", name: "c", color: "", detect: DetectDef(paths: ["~/.covered"], apps: nil, processes: nil),
                              shared: nil, orphanWhenAppMissing: nil, rules: [])
        let found = Discovery.findUnknown(rules: RuleSet(version: 1, updated: "", defaults: .init(historyMaxAgeDays: 30), tools: [covered]), home: home)
        XCTAssertEqual(Set(found.map { ($0.path as NSString).lastPathComponent }), [".newagent", ".mystery", "SuperCopilot"])
    }
}
