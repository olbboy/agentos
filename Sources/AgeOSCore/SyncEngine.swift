import Foundation

/// The orchestrator: source.fetch → store.install → setCurrent → index.upsert.
/// The filesystem is the source of truth; the index is only a cache.
public struct SyncEngine: Sendable {
    public let home: AgeOSHome
    public let store: Store
    public let index: IndexDB
    public let registry: SourcesRegistry
    let http: HTTPClient

    public init(home: AgeOSHome, http: HTTPClient = URLSessionHTTPClient()) throws {
        self.home = home
        try home.ensureLayout()
        self.store = Store(home: home)
        self.index = try IndexDB(path: home.indexPath)
        self.registry = SourcesRegistry(home: home)
        self.http = http
    }

    public struct SyncReport: Sendable, Codable {
        public var sourceId: String
        public var version: String
        public var changed: Bool
        public var installed: [String]
        public var skippedCount: Int
        public var skippedDetails: [String]
        public var archived: Bool
        /// A copy-mode target skipped because the user edited it (drift) — needs `doctor --fix` or --force.
        public var driftWarnings: [String]
    }

    /// Syncs one source, or all of them when `sourceId == nil`.
    public func sync(sourceId: String? = nil) async throws -> [SyncReport] {
        let sources = try registry.load()
        let targets: [SourceDescriptor]
        if let sourceId {
            guard let found = sources.first(where: { $0.id == sourceId }) else {
                throw AgeOSError(.notFound, "Source '\(sourceId)' has not been added",
                                 remedy: "Run `ageos source list`; add one with `ageos source add <url|path>`")
            }
            targets = [found]
        } else {
            targets = sources
        }

        var reports: [SyncReport] = []
        for descriptor in targets {
            reports.append(try await syncOne(descriptor))
        }
        return reports
    }

    func syncOne(_ descriptor: SourceDescriptor) async throws -> SyncReport {
        let provider = registry.provider(for: descriptor, http: http)
        let staging = home.cacheDir.appendingPathComponent("staging-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: staging) }

        let result = try await provider.fetch(staging: staging)
        try registry.update(result.descriptor)
        try index.upsertSource(result.descriptor)

        var installed: [String] = []
        var driftWarnings: [String] = []
        if result.changed {
            var keptIds: [String] = []
            let adapters = try? AdapterRegistry(home: home)
            let linkEngine = adapters.map { LinkEngine(home: home, store: store, adapters: $0) }
            for fetched in result.skills {
                let ref = SkillRef(namespace: result.descriptor.namespace, name: fetched.parsed.manifest.name)
                let previousVersion = store.currentVersion(ref)
                try store.installVersion(ref, version: result.version, from: fetched.parsed.directory)
                try store.setCurrent(ref, version: result.version)
                try store.gcOrphans(ref)
                // Version changed → re-sync enabled copy-mode targets (symlinks follow current on their own).
                if let linkEngine, previousVersion != nil, previousVersion != result.version,
                   let report = try? linkEngine.propagateVersionChange(ref, newVersion: result.version) {
                    driftWarnings.append(contentsOf: report.driftSkipped.map { "\(ref.id) → \($0)" })
                }
                // Re-parse from the store so index.path points into the library, not into staging.
                let storedDir = store.versionDir(ref, version: result.version)
                let parsed = (try? SkillParser.parse(directory: storedDir)) ?? fetched.parsed
                try index.upsertSkill(ref: ref, sourceId: result.descriptor.id, parsed: parsed,
                                      version: result.version, path: store.currentLink(ref).path,
                                      deprecated: result.descriptor.archived)
                installed.append(ref.id)
                keptIds.append(ref.id)
            }
            try index.pruneSkills(sourceId: result.descriptor.id, keeping: keptIds)
        } else if result.descriptor.archived != descriptor.archived {
            // Content unchanged but the archive flag moved → update `deprecated` in the index.
            try index.rebuild(home: home, store: store, registry: registry)
        }

        return SyncReport(sourceId: result.descriptor.id, version: result.version, changed: result.changed,
                          installed: installed, skippedCount: result.skipped.count,
                          skippedDetails: result.skipped.map { "\($0.path): \($0.reason)" },
                          archived: result.descriptor.archived, driftWarnings: driftWarnings)
    }

    /// `ageos source add` — add + sync ngay.
    public func addSource(_ input: String) async throws -> (descriptor: SourceDescriptor, report: SyncReport) {
        let descriptor: SourceDescriptor
        if FileManager.default.fileExists(atPath: (input as NSString).expandingTildeInPath) {
            descriptor = try LocalSource.makeDescriptor(path: input)
        } else {
            descriptor = try GitHubSource.makeDescriptor(url: input)
        }
        let (existing, _) = try registry.add(descriptor)
        let report = try await syncOne(existing)
        return (existing, report)
    }
}
