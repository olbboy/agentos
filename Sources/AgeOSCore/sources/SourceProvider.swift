import Foundation

/// Metadata một nguồn skill — persist trong `sources.json`.
public struct SourceDescriptor: Sendable, Codable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Codable { case github, local }

    /// GitHub: `gh/<owner>/<repo>` · Local: `local/<slug>`.
    public var id: String
    public var kind: Kind
    /// GitHub: URL repo · Local: path tuyệt đối.
    public var location: String
    public var addedAt: Date
    public var lastSync: Date?
    /// Version đã sync gần nhất (commit sha / content hash).
    public var lastVersion: String?
    /// ETag của lần gọi API trước → sync lần 2 thành no-op (304).
    public var etag: String?
    /// Repo upstream đã archive → mọi skill của nguồn này bị flag deprecated.
    public var archived: Bool
    public var stars: Int?
    public var license: String?
    public var pushedAt: Date?

    /// Namespace store cho skill thuộc nguồn này (`owner/repo` | `local/<slug>`).
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

/// Một skill lấy được từ nguồn (đã parse + validate structural).
public struct FetchedSkill: Sendable {
    public let parsed: ParsedSkill
    public init(parsed: ParsedSkill) { self.parsed = parsed }
}

public struct SourceFetchResult: Sendable {
    /// Version toàn nguồn (commit sha / content hash) — mọi skill trong lần fetch dùng chung.
    public var version: String
    /// `false` = không đổi so với lần trước (ETag/hash trùng) → sync no-op.
    public var changed: Bool
    public var skills: [FetchedSkill]
    /// Path SKILL.md bị bỏ qua kèm lý do (log cho user, không nuốt im lặng).
    public var skipped: [(path: String, reason: String)]
    /// Descriptor cập nhật (etag, archived, stars...) để registry persist.
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
    /// Fetch trạng thái mới nhất. `staging` là thư mục tạm provider được phép ghi.
    func fetch(staging: URL) async throws -> SourceFetchResult
}
