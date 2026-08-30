import Foundation
import GRDB

/// Cache SQLite (GRDB) cho search/list nhanh. KHÔNG phải nguồn chân lý —
/// filesystem (store + sources.json + lockfile) mới là; `rebuild()` khôi phục từ FS.
public struct IndexDB: Sendable {
    public let dbQueue: DatabaseQueue

    public init(path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: path.path)
        try migrator.migrate(dbQueue)
    }

    var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "sources") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("location", .text).notNull()
                t.column("last_sync", .datetime)
                t.column("last_version", .text)
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("stars", .integer)
                t.column("license", .text)
            }
            try db.create(table: "skills") { t in
                t.primaryKey("id", .text) // <ns>/<name>
                t.column("source_id", .text).notNull().indexed()
                t.column("name", .text).notNull().indexed()
                t.column("description", .text).notNull()
                t.column("title", .text)
                t.column("version", .text).notNull()
                t.column("path", .text).notNull()
                t.column("deprecated", .boolean).notNull().defaults(to: false)
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "versions") { t in
                t.column("skill_id", .text).notNull().indexed()
                t.column("version", .text).notNull()
                t.column("installed_at", .datetime).notNull()
                t.uniqueKey(["skill_id", "version"])
            }
        }
        m.registerMigration("v2-mcp-health") { db in
            try db.create(table: "mcp_health") { t in
                t.primaryKey("entry_name", .text)
                t.column("checked_at", .datetime).notNull()
                t.column("ok", .boolean).notNull()
                t.column("latency_ms", .integer).notNull()
                t.column("tool_count", .integer).notNull()
                t.column("schema_tokens", .integer).notNull()
                t.column("error", .text)
            }
        }
        return m
    }

    // MARK: - MCP health cache (nuôi Budget Meter)

    public func recordMcpHealth(entryName: String, report: HealthCheck.Report) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO mcp_health (entry_name, checked_at, ok, latency_ms, tool_count, schema_tokens, error)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(entry_name) DO UPDATE SET
                    checked_at = excluded.checked_at, ok = excluded.ok,
                    latency_ms = excluded.latency_ms, tool_count = excluded.tool_count,
                    schema_tokens = excluded.schema_tokens, error = excluded.error
                """, arguments: [entryName, Date(), report.ok, report.latencyMs,
                                 report.toolCount, report.schemaTokens, report.error])
        }
    }

    public func mcpSchemaTokens(entryName: String) throws -> Int? {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT schema_tokens FROM mcp_health WHERE entry_name = ? AND ok = 1",
                             arguments: [entryName])
        }
    }

    // MARK: - Records

    public struct SkillRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
        public static let databaseTableName = "skills"
        public var id: String
        public var sourceId: String
        public var name: String
        public var description: String
        public var title: String?
        public var version: String
        public var path: String
        public var deprecated: Bool
        public var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, name, description, title, version, path, deprecated
            case sourceId = "source_id"
            case updatedAt = "updated_at"
        }
    }

    public struct SourceRow: Codable, Sendable, FetchableRecord, PersistableRecord {
        public static let databaseTableName = "sources"
        public var id: String
        public var kind: String
        public var location: String
        public var lastSync: Date?
        public var lastVersion: String?
        public var archived: Bool
        public var stars: Int?
        public var license: String?

        enum CodingKeys: String, CodingKey {
            case id, kind, location, archived, stars, license
            case lastSync = "last_sync"
            case lastVersion = "last_version"
        }
    }

    // MARK: - Writes

    public func upsertSource(_ d: SourceDescriptor) throws {
        let row = SourceRow(id: d.id, kind: d.kind.rawValue, location: d.location,
                            lastSync: d.lastSync, lastVersion: d.lastVersion,
                            archived: d.archived, stars: d.stars, license: d.license)
        try dbQueue.write { try row.upsert($0) }
    }

    public func upsertSkill(ref: SkillRef, sourceId: String, parsed: ParsedSkill,
                            version: String, path: String, deprecated: Bool) throws {
        let row = SkillRow(id: ref.id, sourceId: sourceId, name: ref.name,
                           description: parsed.manifest.description, title: parsed.title,
                           version: version, path: path,
                           deprecated: deprecated || parsed.manifest.deprecated, updatedAt: Date())
        try dbQueue.write { db in
            try row.upsert(db)
            try db.execute(sql: "INSERT OR IGNORE INTO versions (skill_id, version, installed_at) VALUES (?, ?, ?)",
                           arguments: [ref.id, version, Date()])
        }
    }

    /// Xóa skill của một nguồn không còn xuất hiện sau sync (repo gỡ skill).
    public func pruneSkills(sourceId: String, keeping ids: [String]) throws {
        try dbQueue.write { db in
            if ids.isEmpty {
                try db.execute(sql: "DELETE FROM skills WHERE source_id = ?", arguments: [sourceId])
            } else {
                let placeholders = ids.map { _ in "?" }.joined(separator: ",")
                try db.execute(sql: "DELETE FROM skills WHERE source_id = ? AND id NOT IN (\(placeholders))",
                               arguments: StatementArguments([sourceId] + ids))
            }
        }
    }

    public func removeSource(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM skills WHERE source_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM sources WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Reads

    public func listSkills() throws -> [SkillRow] {
        try dbQueue.read { try SkillRow.order(sql: "id").fetchAll($0) }
    }

    public func findSkill(id: String) throws -> SkillRow? {
        try dbQueue.read { try SkillRow.fetchOne($0, key: id) }
    }

    /// Tìm theo name không namespace (tiện CLI): unique thì trả, nhiều thì ném lỗi liệt kê.
    public func resolveSkill(query: String) throws -> SkillRow {
        if let exact = try findSkill(id: query) { return exact }
        let matches = try dbQueue.read {
            try SkillRow.filter(sql: "name = ?", arguments: [query]).fetchAll($0)
        }
        switch matches.count {
        case 1: return matches[0]
        case 0:
            throw AgeOSError(.notFound, "Không tìm thấy skill '\(query)' trong index",
                             remedy: "Chạy `ageos list` xem skill khả dụng, hoặc `ageos sync` để cập nhật")
        default:
            let ids = matches.map(\.id).joined(separator: ", ")
            throw AgeOSError(.conflict, "'\(query)' khớp nhiều skill: \(ids)",
                             remedy: "Dùng id đầy đủ dạng <owner>/<repo>/<name>")
        }
    }

    public func listSources() throws -> [SourceRow] {
        try dbQueue.read { try SourceRow.order(sql: "id").fetchAll($0) }
    }

    /// Rebuild toàn bộ từ filesystem: store + sources.json.
    public func rebuild(home: AgeOSHome, store: Store, registry: SourcesRegistry) throws {
        let sources = try registry.load()
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM skills")
            try db.execute(sql: "DELETE FROM sources")
            try db.execute(sql: "DELETE FROM versions")
        }
        for d in sources { try upsertSource(d) }
        let sourceByNS = Dictionary(uniqueKeysWithValues: sources.map { ($0.namespace, $0) })
        for (ref, version) in store.listInstalled() {
            let dir = store.versionDir(ref, version: version)
            guard let parsed = try? SkillParser.parse(directory: dir) else { continue }
            let source = sourceByNS[ref.namespace]
            try upsertSkill(ref: ref, sourceId: source?.id ?? "unknown", parsed: parsed,
                            version: version, path: store.currentLink(ref).path,
                            deprecated: source?.archived ?? false)
        }
    }
}
