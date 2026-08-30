import Foundation

/// Danh sách nguồn đã add — persist `sources.json` (sorted, atomic).
public struct SourcesRegistry: Sendable {
    public let home: AgeOSHome

    public init(home: AgeOSHome) {
        self.home = home
    }

    public func load() throws -> [SourceDescriptor] {
        guard let data = FileManager.default.contents(atPath: home.sourcesPath.path) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SourceDescriptor].self, from: data)
        } catch {
            throw AgeOSError(.configUnreadable, "sources.json hỏng: \(error)",
                             remedy: "Sửa tay \(home.sourcesPath.path) hoặc xóa rồi add lại nguồn")
        }
    }

    public func save(_ sources: [SourceDescriptor]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try AtomicFile.write(try encoder.encode(sources.sorted { $0.id < $1.id }), to: home.sourcesPath)
    }

    /// Add mới hoặc trả về descriptor sẵn có (idempotent theo id).
    @discardableResult
    public func add(_ descriptor: SourceDescriptor) throws -> (descriptor: SourceDescriptor, isNew: Bool) {
        var sources = try load()
        if let existing = sources.first(where: { $0.id == descriptor.id }) {
            return (existing, false)
        }
        sources.append(descriptor)
        try save(sources)
        return (descriptor, true)
    }

    public func update(_ descriptor: SourceDescriptor) throws {
        var sources = try load()
        if let i = sources.firstIndex(where: { $0.id == descriptor.id }) {
            sources[i] = descriptor
        } else {
            sources.append(descriptor)
        }
        try save(sources)
    }

    public func remove(id: String) throws -> SourceDescriptor? {
        var sources = try load()
        guard let i = sources.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = sources.remove(at: i)
        try save(sources)
        return removed
    }

    /// Dựng provider tương ứng kind.
    public func provider(for descriptor: SourceDescriptor, http: HTTPClient = URLSessionHTTPClient()) -> any SourceProvider {
        switch descriptor.kind {
        case .github: return GitHubSource(descriptor: descriptor, http: http)
        case .local: return LocalSource(descriptor: descriptor)
        }
    }
}
