import Foundation

public enum Risk: String, Codable, CaseIterable, Sendable {
    case orphan, safe, history, compact, protected

    /// Whether items of this risk can be ticked and moved to the Trash.
    public var isRemovable: Bool { self == .orphan || self == .safe || self == .history }
}

public enum RuleAction: String, Codable, Sendable {
    case trash
    case ageFilter = "age-filter"
    case vacuum
    case none
}

public struct RuleDef: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let label: String
    public let paths: [String]
    public let risk: Risk
    public let action: RuleAction
    public let explain: String
    /// Session format this rule's files can be exported as ("claude", "codex").
    public let export: String?
    /// "appMissing": only applies when the tool's app is not installed.
    public let onlyWhen: String?
    /// Age filtering granularity: "file" (default) checks every file, "entry" keeps or drops each matched entry whole.
    public let ageUnit: String?
}

public struct DetectDef: Codable, Sendable, Hashable {
    public let paths: [String]?
    public let apps: [String]?
    public let processes: [String]?
}

public struct ToolDef: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let color: String
    public let detect: DetectDef
    public let shared: Bool?
    public let orphanWhenAppMissing: Bool?
    public let rules: [RuleDef]
}

public struct RuleSet: Codable, Sendable {
    public struct Defaults: Codable, Sendable {
        public let historyMaxAgeDays: Int
        public init(historyMaxAgeDays: Int) { self.historyMaxAgeDays = historyMaxAgeDays }
    }
    public let version: Int
    public let updated: String
    public let defaults: Defaults
    public let tools: [ToolDef]

    public init(version: Int, updated: String, defaults: Defaults, tools: [ToolDef]) {
        self.version = version
        self.updated = updated
        self.defaults = defaults
        self.tools = tools
    }

    public static func bundled() throws -> RuleSet {
        guard let url = Bundle.module.url(forResource: "rules", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(RuleSet.self, from: Data(contentsOf: url))
    }
}
