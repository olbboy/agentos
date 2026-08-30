import Foundation

/// Adapter data-driven: MỌI hiểu biết per-agent (path, capability symlink, config MCP)
/// nằm trong JSON — thêm/sửa agent = sửa data, không sửa Swift, không cần release.
public struct AdapterSpec: Sendable, Codable, Equatable, Identifiable {
    public var schemaVersion: Int
    public var id: String
    public var displayName: String
    /// Path tồn tại → coi như agent có trên máy.
    public var detect: [String]
    public var skills: SkillsBlock?
    public var mcp: McpBlock?
    public var budget: BudgetBlock?
    public var notes: String?

    public struct SkillsBlock: Sendable, Codable, Equatable {
        public var globalPath: String
        /// Tương đối với project root (vd `.claude/skills`).
        public var projectPath: String?
        /// Path phụ agent cũng đọc (effective-load scan) — KHÔNG phải target ghi.
        public var compatPaths: [String]?
        public var folderSymlink: Bool
        public var fileSymlink: Bool
        public var preferredMode: LinkModeSpec
        /// Đã xác minh trên máy thật (spike/doctor) hay chỉ từ docs.
        public var verified: Bool
    }

    public enum LinkModeSpec: String, Sendable, Codable {
        case symlink, copy
    }

    public struct McpBlock: Sendable, Codable, Equatable {
        public var configPath: String
        public var projectConfigPath: String?
        public var format: ConfigFormat
        /// Key chứa map servers (`mcpServers` JSON / `mcp_servers` TOML).
        public var keyPath: String
        public var verified: Bool
    }

    public enum ConfigFormat: String, Sendable, Codable {
        case json, toml
    }

    public struct BudgetBlock: Sendable, Codable, Equatable {
        public var catalogTokensWarn: Int?
        /// Agent cắt description trong catalog prompt (0 = không cắt).
        public var descriptionTruncateChars: Int?
    }

    /// Agent có mặt trên máy này không (một trong các detect path tồn tại).
    public func isDetected(fileManager: FileManager = .default) -> Bool {
        detect.contains { fileManager.fileExists(atPath: AgeOSHome.expand($0).path) }
    }

    /// Mode enable hiệu lực: preferredMode, nhưng symlink chỉ khi agent thật sự hỗ trợ.
    public var effectiveSkillMode: LinkModeSpec {
        guard let skills else { return .copy }
        if skills.preferredMode == .symlink && !skills.folderSymlink { return .copy }
        return skills.preferredMode
    }
}
