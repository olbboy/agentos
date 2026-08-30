import Foundation
import TOMLKit

/// The Context Budget Meter: how many catalog tokens each skill and MCP server costs an
/// agent BEFORE the user types anything. The 4 bytes-per-token factor comes from a spike and
/// matches how grok estimates it, ±20% — every number here is an ESTIMATE and the UI must say so.
public struct BudgetMeter: Sendable {
    public let adapters: AdapterRegistry
    /// Looks up schema tokens from a health run (entry name → tokens).
    public let mcpSchemaTokens: @Sendable (String) -> Int?

    public init(adapters: AdapterRegistry, mcpSchemaTokens: @escaping @Sendable (String) -> Int? = { _ in nil }) {
        self.adapters = adapters
        self.mcpSchemaTokens = mcpSchemaTokens
    }

    public struct Report: Sendable, Codable {
        public var adapterId: String
        public var skillCount: Int
        public var skillTokens: Int
        public var topSkills: [Entry]
        public var mcpCount: Int
        public var mcpTokens: Int
        public var mcpUnknownHealth: [String]
        public var totalTokens: Int
        public var warnThreshold: Int?
        public var warnings: [String]

        public struct Entry: Sendable, Codable {
            public var name: String
            public var tokens: Int
        }
    }

    /// What one skill costs a specific agent's catalog: name plus description (truncated the
    /// way that adapter truncates) plus roughly 30 characters of surrounding format.
    ///
    /// Deliberately `public`: the SwiftUI app shows an estimate per Library row and must
    /// REUSE this exact formula. Duplicating it in the app is the sure road to two different
    /// numbers for the same skill.
    public static func skillTokens(name: String, description: String, truncateChars: Int) -> Int {
        let descChars = truncateChars > 0 ? min(description.count, truncateChars) : description.count
        return (name.count + descChars + 30) / 4
    }

    public func compute(adapterId: String) throws -> Report {
        let adapter = try adapters.adapter(id: adapterId)
        let scanner = EffectiveLoadScanner(adapters: adapters)
        let inventory = scanner.scan()
        let truncate = adapter.budget?.descriptionTruncateChars ?? 0
        var warnings: [String] = []

        // Skills: counted by distinct name (an agent dedupes by name across paths).
        var entries: [Report.Entry] = []
        if let agent = inventory.agents.first(where: { $0.adapterId == adapterId }) {
            var seen = Set<String>()
            for skill in agent.entries where !seen.contains(skill.name) {
                seen.insert(skill.name)
                entries.append(.init(name: skill.name,
                                     tokens: Self.skillTokens(name: skill.name,
                                                              description: skill.description,
                                                              truncateChars: truncate)))
            }
            for (name, paths) in agent.duplicated.sorted(by: { $0.key < $1.key }) {
                warnings.append("'\(name)' appears at \(paths.count) paths — only one copy is loaded, but they should be merged (see `ageos scan`)")
            }
        }
        entries.sort { $0.tokens > $1.tokens }
        let skillTokens = entries.reduce(0) { $0 + $1.tokens }

        // MCP: read the client config read-only; the cost is the schema tokens from health.
        var mcpEntries: [String] = []
        if let mcp = adapter.mcp {
            mcpEntries = (try? Self.readMcpEntryNames(configPath: AgeOSHome.expand(mcp.configPath),
                                                      format: mcp.format, keyPath: mcp.keyPath)) ?? []
        }
        var mcpTokens = 0
        var unknownHealth: [String] = []
        for name in mcpEntries {
            if let tokens = mcpSchemaTokens(name) {
                mcpTokens += tokens
            } else {
                unknownHealth.append(name)
            }
        }
        if !unknownHealth.isEmpty {
            warnings.append("No schema measurement yet for \(unknownHealth.count) MCP server(s) (\(unknownHealth.sorted().joined(separator: ", "))) — run `ageos mcp health <name>` to measure")
        }

        let total = skillTokens + mcpTokens
        let threshold = adapter.budget?.catalogTokensWarn
        if let threshold, total > threshold {
            warnings.append("Catalog ≈\(total) tokens exceeds the \(threshold) threshold for \(adapterId) — risk of context dilution and silent drops; disable some entries or move them to project scope")
        }

        return Report(adapterId: adapterId, skillCount: entries.count, skillTokens: skillTokens,
                      topSkills: Array(entries.prefix(10)), mcpCount: mcpEntries.count,
                      mcpTokens: mcpTokens, mcpUnknownHealth: unknownHealth.sorted(),
                      totalTokens: total, warnThreshold: threshold, warnings: warnings)
    }

    /// Reads the LIST of MCP entry names from a client config — strictly read-only.
    static func readMcpEntryNames(configPath: URL, format: AdapterSpec.ConfigFormat, keyPath: String) throws -> [String] {
        guard let data = FileManager.default.contents(atPath: configPath.path) else { return [] }
        switch format {
        case .json:
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let servers = root[keyPath] as? [String: Any] else { return [] }
            return servers.keys.sorted()
        case .toml:
            guard let text = String(data: data, encoding: .utf8),
                  let table = try? TOMLTable(string: text),
                  let servers = table[keyPath]?.table else { return [] }
            return servers.keys.sorted()
        }
    }
}
