import Foundation

/// `ageos.lock.json` — remembers versions and where things were enabled (target, scope,
/// linkMode) so update, disable and doctor know exactly what AgeOS created and leave the
/// user's own files alone. Serialized stably (sorted keys) so it diffs cleanly in git.
public struct Lockfile: Sendable, Codable, Equatable {
    public var schemaVersion: Int
    public var skills: [String: SkillEntry]
    public var mcpServers: [String: McpEntry]

    public struct SkillEntry: Sendable, Codable, Equatable {
        public var source: String
        public var version: String
        /// The key is `<adapterId>@global` or `<adapterId>@<projectPath>`.
        public var targets: [String: TargetState]

        public init(source: String, version: String, targets: [String: TargetState] = [:]) {
            self.source = source
            self.version = version
            self.targets = targets
        }
    }

    public struct TargetState: Sendable, Codable, Equatable {
        /// `config` = an entry written into a client's config file (MCP), not a link on disk.
        public enum LinkMode: String, Sendable, Codable { case symlink, copy, config }
        public var scope: String
        public var linkMode: LinkMode
        /// The absolute path where the skill appears inside the agent's folder.
        public var path: String
        /// Copy mode: a hash per file, to detect drift.
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
        /// Env keys marked sensitive (the values are still plaintext at MVP — Keychain is v1.1).
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

    /// Target-key helpers.
    public static func targetKey(adapter: String, projectPath: String?) -> String {
        projectPath.map { "\(adapter)@\($0)" } ?? "\(adapter)@global"
    }
}
