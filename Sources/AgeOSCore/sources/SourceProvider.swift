import Foundation

/// The metadata of one skill source — persisted in `sources.json`.
public struct SourceDescriptor: Sendable, Codable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Codable { case github, local }

    /// GitHub: `gh/<owner>/<repo>` · Local: `local/<slug>`.
    public var id: String
    public var kind: Kind
    /// GitHub: the repo URL · Local: an absolute path.
    public var location: String
    public var addedAt: Date
    public var lastSync: Date?
    /// The most recently synced version (commit sha or content hash).
    public var lastVersion: String?
    /// The ETag from the previous API call → a second sync becomes a no-op (304).
    public var etag: String?
    /// The upstream repo was archived → every skill from this source is flagged deprecated.
    public var archived: Bool
    public var stars: Int?
    public var license: String?
    public var pushedAt: Date?

    /// The store namespace for skills from this source (`owner/repo` or `local/<slug>`).
    public var namespace: String {
        switch kind {
        case .github: return String(id.dropFirst("gh/".count))
        case .local: return id
        }
    }

    public init(id: String, kind: Kind, location: String, addedAt: Date = Date(),
                lastSync: Date? = nil, lastVersion: String? = nil, etag: String? = nil,
                archived: Bool = false, stars: Int? = nil, license: String? = nil, pushedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.location = location
        self.addedAt = addedAt
        self.lastSync = lastSync
        self.lastVersion = lastVersion
        self.etag = etag
        self.archived = archived
        self.stars = stars
        self.license = license
        self.pushedAt = pushedAt
    }
}

/// One skill fetched from a source (parsed and structurally validated).
public struct FetchedSkill: Sendable {
    public let parsed: ParsedSkill
    public init(parsed: ParsedSkill) { self.parsed = parsed }
}

public struct SourceFetchResult: Sendable {
    /// The source-wide version (commit sha or content hash) — shared by every skill in one fetch.
    public var version: String
    /// `false` = unchanged since last time (matching ETag or hash) → the sync is a no-op.
    public var changed: Bool
    public var skills: [FetchedSkill]
    /// A skipped SKILL.md path plus the reason (logged for the user, never swallowed).
    public var skipped: [(path: String, reason: String)]
    /// The updated descriptor (etag, archived, stars…) for the registry to persist.
    public var descriptor: SourceDescriptor

    public init(version: String, changed: Bool, skills: [FetchedSkill],
                skipped: [(path: String, reason: String)], descriptor: SourceDescriptor) {
        self.version = version
        self.changed = changed
        self.skills = skills
        self.skipped = skipped
        self.descriptor = descriptor
    }
}

public protocol SourceProvider: Sendable {
    var descriptor: SourceDescriptor { get }
    /// Fetches the latest state. `staging` is a temp directory the provider may write into.
    func fetch(staging: URL) async throws -> SourceFetchResult
}
