import Foundation

/// The frontmatter of SKILL.md, per the agentskills.io spec.
/// Unknown fields are not discarded — they stay in `extra` so they round-trip and the scanner can use them later.
public struct SkillManifest: Sendable, Codable, Equatable {
    public var name: String
    public var description: String
    public var license: String?
    public var allowedTools: [String]?
    public var metadata: [String: String]
    public var deprecated: Bool
    /// Fields outside the spec (stringified) — for example `version`, `author`.
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

/// A parsed skill: manifest, body content, and where it sits on disk.
public struct ParsedSkill: Sendable, Equatable {
    public var manifest: SkillManifest
    public var body: String
    public var directory: URL
    /// The first H1 in the body, if any — used for display.
    public var title: String?

    public init(manifest: SkillManifest, body: String, directory: URL, title: String? = nil) {
        self.manifest = manifest
        self.body = body
        self.directory = directory
        self.title = title
    }
}
