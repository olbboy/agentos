import Foundation

/// Joins the intelligence pieces into a single pass: effective-load → dedupe
/// (exact + near) → deprecated → lint. STATIC ONLY — nothing from a skill is executed.
public struct ScanEngine: Sendable {
    public let home: AgeOSHome
    public let adapters: AdapterRegistry
    public let index: IndexDB
    public var dedupe: DedupeEngine

    public init(home: AgeOSHome, adapters: AdapterRegistry, index: IndexDB,
                dedupe: DedupeEngine = DedupeEngine()) {
        self.home = home
        self.adapters = adapters
        self.index = index
        self.dedupe = dedupe
    }

    public struct ScanReport: Sendable, Codable {
        public var scannedSkills: Int
        public var exactDupes: [DedupeEngine.DupePair]
        public var nearDupes: [DedupeEngine.DupePair]
        /// nil = the machine has no embedding assets (near-duplicate detection skipped, and noted).
        public var nearDupeAvailable: Bool
        public var deprecated: [DeprecatedItem]
        public var lintFindings: [LintItem]
        public var notes: [String]

        public struct DeprecatedItem: Sendable, Codable {
            public var id: String
            public var reason: String
        }

        public struct LintItem: Sendable, Codable {
            public var id: String
            public var findings: [DescriptionLinter.Finding]
        }
    }

    public func run() throws -> ScanReport {
        var notes: [String] = []

        // 1) Gather items from the effective-load scan (every path, every agent), deduped by canonical path.
        let scanner = EffectiveLoadScanner(adapters: adapters)
        let inventory = scanner.scan()
        var itemsByPath: [String: DedupeEngine.Item] = [:]
        for agent in inventory.agents {
            for entry in agent.entries {
                let canonical = entry.path.canonicalFilePath
                guard itemsByPath[canonical] == nil else { continue }
                let dir = URL(fileURLWithPath: entry.path, isDirectory: true)
                if let parsed = try? SkillParser.parse(directory: dir) {
                    itemsByPath[canonical] = .from(parsed, id: "\(entry.name) @ \(entry.path)")
                }
            }
        }
        let items = itemsByPath.values.sorted { $0.id < $1.id }

        // 2) Dedupe.
        let exact = dedupe.exactDupes(items)
        let near: [DedupeEngine.DupePair]
        let nearAvailable: Bool
        if let n = dedupe.nearDupes(items) {
            // Drop pairs already caught as exact (near always contains exact, since cosine ~1 after centering).
            let exactKeys = Set(exact.map { "\($0.a)|\($0.b)" })
            near = n.filter { !exactKeys.contains("\($0.a)|\($0.b)") }
            nearAvailable = true
        } else {
            near = []
            nearAvailable = false
            notes.append("Embedding assets unavailable — near-duplicate detection skipped (exact only)")
        }

        // 3) Deprecated: index (repo archived) + frontmatter.
        var deprecated: [ScanReport.DeprecatedItem] = []
        for row in (try? index.listSkills()) ?? [] where row.deprecated {
            deprecated.append(.init(id: row.id, reason: "source archived, or frontmatter marks it deprecated"))
        }
        for item in items {
            if let dir = item.directory, let parsed = try? SkillParser.parse(directory: dir),
               parsed.manifest.deprecated {
                let id = item.id
                if !deprecated.contains(where: { $0.id == id }) {
                    deprecated.append(.init(id: id, reason: "frontmatter deprecated: true"))
                }
            }
        }

        // 4) Lint descriptions (reporting only the skills that actually have findings).
        var lintItems: [ScanReport.LintItem] = []
        for item in items {
            let findings = DescriptionLinter.lint(name: item.name, description: item.description)
            if !findings.isEmpty {
                lintItems.append(.init(id: item.id, findings: findings))
            }
        }

        return ScanReport(scannedSkills: items.count, exactDupes: exact, nearDupes: near,
                          nearDupeAvailable: nearAvailable, deprecated: deprecated,
                          lintFindings: lintItems, notes: notes)
    }
}
