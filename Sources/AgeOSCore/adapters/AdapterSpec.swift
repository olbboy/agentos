import Foundation

/// A data-driven adapter: EVERY per-agent fact (paths, symlink capability, MCP config)
/// lives in JSON — adding or fixing an agent means editing data, not Swift, and needs no release.
public struct AdapterSpec: Sendable, Codable, Equatable, Identifiable {
    public var schemaVersion: Int
    public var id: String
    public var displayName: String
    /// If the path exists, the agent is treated as present on this machine.
    public var detect: [String]
    public var skills: SkillsBlock?
    public var mcp: McpBlock?
    public var budget: BudgetBlock?
    public var notes: String?

    public struct SkillsBlock: Sendable, Codable, Equatable {
        public var globalPath: String
        /// Relative to the project root (for example `.claude/skills`).
        public var projectPath: String?
        /// Extra paths the agent also reads (for the effective-load scan) — NOT write targets.
        public var compatPaths: [String]?
        public var folderSymlink: Bool
        public var fileSymlink: Bool
        public var preferredMode: LinkModeSpec
        /// Whether this was verified on a real machine (spike or doctor), or only taken from docs.
        public var verified: Bool
    }

    public enum LinkModeSpec: String, Sendable, Codable {
        case symlink, copy
    }

    public struct McpBlock: Sendable, Codable, Equatable {
        public var configPath: String
        public var projectConfigPath: String?
        public var format: ConfigFormat
        /// The key holding the server map (`mcpServers` in JSON, `mcp_servers` in TOML).
        public var keyPath: String
        public var verified: Bool
    }

    public enum ConfigFormat: String, Sendable, Codable {
        case json, toml
    }

    public struct BudgetBlock: Sendable, Codable, Equatable {
        public var catalogTokensWarn: Int?
        /// Where the agent truncates a description in its catalog prompt (0 = no truncation).
        public var descriptionTruncateChars: Int?
    }

    /// Whether the agent is present on this machine (one of the detect paths exists).
    public func isDetected(fileManager: FileManager = .default) -> Bool {
        detect.contains { fileManager.fileExists(atPath: AgeOSHome.expand($0).path) }
    }

    /// The effective enable mode: preferredMode, but symlink only when the agent really supports it.
    public var effectiveSkillMode: LinkModeSpec {
        guard let skills else { return .copy }
        if skills.preferredMode == .symlink && !skills.folderSymlink { return .copy }
        return skills.preferredMode
    }
}
