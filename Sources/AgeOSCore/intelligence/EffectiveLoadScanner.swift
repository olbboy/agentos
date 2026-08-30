import Foundation

/// Quét HIỆN TRẠNG thật: agent nào đang load skill gì, từ path nào.
/// Điểm mấu chốt: một agent đọc NHIỀU path (grok đọc 4+ nguồn kể cả compat Claude),
/// nên cùng một skill có thể bị load lặp — scanner phơi ra điều đó.
///
/// AN TOÀN: chỉ ĐỌC file (static). Tuyệt đối không spawn process, không execute
/// bất kỳ nội dung nào trong skill.
public struct EffectiveLoadScanner: Sendable {
    public let adapters: AdapterRegistry

    public init(adapters: AdapterRegistry) {
        self.adapters = adapters
    }

    public struct LoadedSkill: Sendable, Codable {
        public var name: String
        public var description: String
        public var path: String
        /// `managed` = AgeOS tạo (marker/manifest) · `user` = đồ user tự cài.
        public var managed: Bool
        /// Path nguồn là globalPath chính hay compat path.
        public var origin: String
    }

    public struct AgentLoad: Sendable, Codable {
        public var adapterId: String
        public var entries: [LoadedSkill]
        /// name → các path cùng cung cấp skill đó trong agent này (≥2 = trùng).
        public var duplicated: [String: [String]]
    }

    public struct Inventory: Sendable, Codable {
        public var agents: [AgentLoad]
        /// name → agents đang load nó (cross-agent view).
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

    /// Đọc một thư mục chứa nhiều skill dir (mỗi dir con có SKILL.md).
    /// Plugin cache (marketplaces) lồng sâu hơn → dò đệ quy có giới hạn.
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

    /// Import skill user tự cài (không managed) vào library nguồn `local/adopted`.
    /// Copy vào `~/.ageos/adopted/` rồi add + sync như nguồn local bình thường —
    /// KHÔNG đụng bản gốc trong thư mục agent.
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
                    // Copy resolve symlink (bản chất nội dung) — đồ gốc giữ nguyên.
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
