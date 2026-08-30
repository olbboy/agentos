import Foundation

/// Scans what is ACTUALLY happening: which agent loads which skill, from which path.
/// The key point: one agent reads SEVERAL paths (grok reads 4+ sources, including Claude's
/// compat paths), so the same skill can be loaded more than once — the scanner exposes that.
///
/// SAFETY: it only READS files (static). It never spawns a process and never executes
/// anything inside a skill.
public struct EffectiveLoadScanner: Sendable {
    public let adapters: AdapterRegistry

    public init(adapters: AdapterRegistry) {
        self.adapters = adapters
    }

    public struct LoadedSkill: Sendable, Codable {
        public var name: String
        public var description: String
        public var path: String
        /// `managed` = created by AgeOS (marker or manifest) · `user` = installed by the user.
        public var managed: Bool
        /// Whether the source path is the main globalPath or a compat path.
        public var origin: String
    }

    public struct AgentLoad: Sendable, Codable {
        public var adapterId: String
        public var entries: [LoadedSkill]
        /// name → the paths providing that skill inside this agent (2 or more = duplicated).
        public var duplicated: [String: [String]]
    }

    public struct Inventory: Sendable, Codable {
        public var agents: [AgentLoad]
        /// name → the agents loading it (the cross-agent view).
        public var byName: [String: [String]]
        public var totalDistinctSkills: Int
        public var totalLoadEntries: Int
    }

    public func scan() -> Inventory {
        var agents: [AgentLoad] = []
        for adapter in adapters.detected() {
            guard let skills = adapter.skills else { continue }
            var entries: [LoadedSkill] = []
            var seenPaths = Set<String>()

            var scanDirs: [(URL, String)] = [(AgeOSHome.expand(skills.globalPath), "global")]
            for compat in skills.compatPaths ?? [] {
                scanDirs.append((AgeOSHome.expand(compat), "compat:\(compat)"))
            }

            for (dir, origin) in scanDirs {
                let canonical = dir.canonicalPath
                guard !seenPaths.contains(canonical) else { continue }
                seenPaths.insert(canonical)
                entries.append(contentsOf: scanSkillDir(dir, origin: origin))
            }

            var byName: [String: [String]] = [:]
            for e in entries {
                byName[e.name, default: []].append(e.path)
            }
            let duplicated = byName.filter { $0.value.count >= 2 }
            agents.append(AgentLoad(adapterId: adapter.id, entries: entries.sorted { $0.name < $1.name },
                                    duplicated: duplicated))
        }

        var byName: [String: [String]] = [:]
        for agent in agents {
            for name in Set(agent.entries.map(\.name)) {
                byName[name, default: []].append(agent.adapterId)
            }
        }
        return Inventory(agents: agents, byName: byName,
                         totalDistinctSkills: byName.count,
                         totalLoadEntries: agents.reduce(0) { $0 + $1.entries.count })
    }

    /// Reads one directory holding several skill directories (each subdirectory has a SKILL.md).
    /// Plugin caches (marketplaces) nest deeper → recurse, but with a depth limit.
    func scanSkillDir(_ dir: URL, origin: String) -> [LoadedSkill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        var result: [LoadedSkill] = []

        func probe(_ candidate: URL, depth: Int) {
            guard depth <= 4 else { return }
            let skillFile = candidate.appendingPathComponent("SKILL.md")
            if fm.fileExists(atPath: skillFile.path) {
                guard let parsed = try? SkillParser.parse(directory: candidate) else { return }
                let managed = ManagedMarker.isSet(on: candidate.path)
                    || CopySync.readManifest(at: candidate) != nil
                result.append(LoadedSkill(name: parsed.manifest.name.isEmpty
                                            ? candidate.lastPathComponent : parsed.manifest.name,
                                          description: parsed.manifest.description,
                                          path: candidate.path, managed: managed, origin: origin))
                return
            }
            guard let children = try? fm.contentsOfDirectory(at: candidate, includingPropertiesForKeys: [.isDirectoryKey],
                                                             options: [.skipsHiddenFiles]) else { return }
            for child in children where child.hasDirectoryPath {
                if SkillScanner.ignoredDirs.contains(child.lastPathComponent) { continue }
                probe(child, depth: depth + 1)
            }
        }

        guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles]) else { return [] }
        for child in children where child.hasDirectoryPath {
            probe(child, depth: 1)
        }
        return result
    }

    // MARK: - Adopt

    public struct AdoptReport: Sendable, Codable {
        public var imported: [String]
        public var skippedManaged: Int
        public var errors: [String]
    }

    /// Imports skills the user installed themselves (not managed) into the `local/adopted` source.
    /// Copies them into `~/.ageos/adopted/`, then adds and syncs them like any local source —
    /// the originals inside the agent folders are NEVER touched.
    public func adoptImport(home: AgeOSHome, engine: SyncEngine) async throws -> AdoptReport {
        let inventory = scan()
        let adoptedDir = home.root.appendingPathComponent("adopted", isDirectory: true)
        try FileManager.default.createDirectory(at: adoptedDir, withIntermediateDirectories: true)
        var imported: [String] = []
        var skippedManaged = 0
        var errors: [String] = []
        var seen = Set<String>()

        for agent in inventory.agents {
            for entry in agent.entries {
                if entry.managed { skippedManaged += 1; continue }
                guard !seen.contains(entry.name) else { continue }
                seen.insert(entry.name)
                let dest = adoptedDir.appendingPathComponent(entry.name, isDirectory: true)
                do {
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    // Copy with symlinks resolved (the content itself) — the original is left alone.
                    try FileManager.default.copyItem(at: URL(fileURLWithPath: entry.path).resolvingSymlinksInPath(),
                                                     to: dest)
                    imported.append(entry.name)
                } catch {
                    errors.append("\(entry.name): \(error)")
                }
            }
        }

        if !imported.isEmpty {
            _ = try await engine.addSource(adoptedDir.path)
        }
        return AdoptReport(imported: imported.sorted(), skippedManaged: skippedManaged, errors: errors)
    }
}
