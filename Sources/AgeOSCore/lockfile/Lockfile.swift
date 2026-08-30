import Foundation

/// `ageos.lock.json` — nhớ version + nơi đã enable (target, scope, linkMode)
/// để update/disable/doctor biết chính xác AgeOS đã tạo gì, không đụng đồ user.
/// Serialize ổn định (sorted keys) để diff được trong git.
public struct Lockfile: Sendable, Codable, Equatable {
    public var schemaVersion: Int
    public var skills: [String: SkillEntry]
    public var mcpServers: [String: McpEntry]

    public struct SkillEntry: Sendable, Codable, Equatable {
        public var source: String
        public var version: String
        /// Key: `<adapterId>@global` hoặc `<adapterId>@<projectPath>`.
        public var targets: [String: TargetState]

        public init(source: String, version: String, targets: [String: TargetState] = [:]) {
            self.source = source
            self.version = version
            self.targets = targets
        }
    }

    public struct TargetState: Sendable, Codable, Equatable {
        /// `config` = entry ghi trong file config client (MCP), không phải link trên FS.
        public enum LinkMode: String, Sendable, Codable { case symlink, copy, config }
        public var scope: String
        public var linkMode: LinkMode
        /// Path tuyệt đối nơi skill xuất hiện trong thư mục agent.
        public var path: String
        /// Copy mode: hash từng file để detect drift (Phase 3).
        public var manifestSha256: String?

        public init(scope: String, linkMode: LinkMode, path: String, manifestSha256: String? = nil) {
            self.scope = scope
            self.linkMode = linkMode
            self.path = path
            self.manifestSha256 = manifestSha256
        }
    }

    public struct McpEntry: Sendable, Codable, Equatable {
        public var source: String
        public var version: String
        /// Key env được đánh dấu nhạy cảm (giá trị vẫn plaintext ở MVP — Keychain là v1.1).
        public var sensitiveEnv: [String]
        public var targets: [String: TargetState]

        public init(source: String, version: String, sensitiveEnv: [String] = [], targets: [String: TargetState] = [:]) {
            self.source = source
            self.version = version
            self.sensitiveEnv = sensitiveEnv
            self.targets = targets
        }
    }

    public init(schemaVersion: Int = 1, skills: [String: SkillEntry] = [:], mcpServers: [String: McpEntry] = [:]) {
        self.schemaVersion = schemaVersion
        self.skills = skills
        self.mcpServers = mcpServers
    }

    // MARK: - IO

    public static func load(from url: URL) throws -> Lockfile {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            return Lockfile()
        }
        do {
            return try JSONDecoder().decode(Lockfile.self, from: data)
        } catch {
            throw AgeOSError(.lockfileCorrupt, "ageos.lock.json is malformed: \(error)",
                             remedy: "Fix it by hand, or delete it and run `ageos reindex` plus re-enable; a backup sits next to the file")
        }
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(try encoder.encode(self), to: url)
    }

    /// Tiện ích key target.
    public static func targetKey(adapter: String, projectPath: String?) -> String {
        projectPath.map { "\(adapter)@\($0)" } ?? "\(adapter)@global"
    }
}
