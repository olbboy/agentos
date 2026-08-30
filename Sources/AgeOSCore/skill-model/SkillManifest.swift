import Foundation

/// Frontmatter của SKILL.md theo spec agentskills.io.
/// Field lạ không bị vứt — giữ trong `extra` để round-trip và cho scanner dùng sau.
public struct SkillManifest: Sendable, Codable, Equatable {
    public var name: String
    public var description: String
    public var license: String?
    public var allowedTools: [String]?
    public var metadata: [String: String]
    public var deprecated: Bool
    /// Field ngoài spec (stringified) — ví dụ `version`, `author`.
    public var extra: [String: String]

    public init(
        name: String,
        description: String,
        license: String? = nil,
        allowedTools: [String]? = nil,
        metadata: [String: String] = [:],
        deprecated: Bool = false,
        extra: [String: String] = [:]
    ) {
        self.name = name
        self.description = description
        self.license = license
        self.allowedTools = allowedTools
        self.metadata = metadata
        self.deprecated = deprecated
        self.extra = extra
    }
}

/// Một skill đã parse: manifest + nội dung body + vị trí trên đĩa.
public struct ParsedSkill: Sendable, Equatable {
    public var manifest: SkillManifest
    public var body: String
    public var directory: URL
    /// Tiêu đề H1 đầu tiên trong body (nếu có) — dùng cho hiển thị.
    public var title: String?

    public init(manifest: SkillManifest, body: String, directory: URL, title: String? = nil) {
        self.manifest = manifest
        self.body = body
        self.directory = directory
        self.title = title
    }
}
