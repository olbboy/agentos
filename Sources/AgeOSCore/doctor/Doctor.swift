import Foundation

/// Examines drift between the lockfile and the real filesystem, repairable with `--fix`:
/// broken link → re-link · copy drift → re-copy (only with --fix, and it says so) ·
/// orphan file (carries the AgeOS marker but the lockfile does not know it) → remove ·
/// destination gone → recreate · agent path gone → warn.
public struct Doctor: Sendable {
    public let home: AgeOSHome
    public let store: Store
    public let adapters: AdapterRegistry

    public init(home: AgeOSHome, store: Store, adapters: AdapterRegistry) {
        self.home = home
        self.store = store
        self.adapters = adapters
    }

    public struct Finding: Sendable, Codable {
        public enum Kind: String, Sendable, Codable {
            case brokenLink = "broken_link"
            case missingTarget = "missing_target"
            case copyDrift = "copy_drift"
            case orphanFile = "orphan_file"
            case agentPathMissing = "agent_path_missing"
            case userShadow = "user_shadow"
            case storeMissing = "store_missing"
            case adapterUnknown = "adapter_unknown"
        }
        public var kind: Kind
        public var skillId: String?
        public var targetKey: String?
        public var path: String
        public var message: String
        public var fixable: Bool
        public var fixed: Bool
    }

    public func run(fix: Bool) throws -> [Finding] {
        var findings: [Finding] = []
        let fm = FileManager.default
        let lock = try Lockfile.load(from: home.lockfilePath)
        let engine = LinkEngine(home: home, store: store, adapters: adapters)

        // 1) Compare each lockfile entry against the filesystem.
        for (skillId, entry) in lock.skills.sorted(by: { $0.key < $1.key }) {
            guard let ref = SkillRef(id: skillId) else { continue }
            let storeOK = store.currentVersion(ref) != nil
            if !storeOK {
                findings.append(.init(kind: .storeMissing, skillId: skillId, targetKey: nil,
                                      path: store.skillDir(ref).path,
                                      message: "Skill is gone from the store but still in the lockfile — run `ageos sync` to fetch it again",
                                      fixable: false, fixed: false))
            }

            for (key, target) in entry.targets.sorted(by: { $0.key < $1.key }) {
                let parts = key.split(separator: "@", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let adapterId = parts[0]
                let projectPath: String? = parts[1] == "global" ? nil : parts[1]
                guard (try? adapters.adapter(id: adapterId)) != nil else {
                    findings.append(.init(kind: .adapterUnknown, skillId: skillId, targetKey: key, path: target.path,
                                          message: "Adapter '\(adapterId)' is no longer in the registry",
                                          fixable: false, fixed: false))
                    continue
                }

                let dest = URL(fileURLWithPath: target.path)
                let linkDestination = try? fm.destinationOfSymbolicLink(atPath: dest.path)
                let exists = fm.fileExists(atPath: dest.path) || linkDestination != nil

                if !exists {
                    var fixed = false
                    var fixNote = ""
                    if fix && storeOK {
                        do {
                            _ = try engine.enable(ref, sourceId: entry.source, adapterId: adapterId,
                                                  project: projectPath.map { URL(fileURLWithPath: $0, isDirectory: true) },
                                                  modeOverride: target.linkMode == .symlink ? .symlink : .copy)
                            fixed = true
                        } catch {
                            fixNote = " — fix FAILED: \(error)"
                        }
                    }
                    findings.append(.init(kind: .missingTarget, skillId: skillId, targetKey: key, path: target.path,
                                          message: "The enable destination disappeared" + (fixed ? " — recreated" : fixNote),
                                          fixable: storeOK, fixed: fixed))
                    continue
                }

                switch target.linkMode {
                case .config:
                    break // an MCP entry in a client config — enable/disable manages those; doctor's skill pass leaves them alone
                case .symlink:
                    // The link exists but its destination is dead (store moved or gone) → re-link.
                    var resolved = dest.resolvingSymlinksInPath()
                    if linkDestination != nil, !fm.fileExists(atPath: resolved.path) {
                        var fixed = false
                        if fix && storeOK {
                            try? fm.removeItem(at: dest)
                            try? fm.createSymbolicLink(atPath: dest.path,
                                                       withDestinationPath: store.currentLink(ref).path)
                            ManagedMarker.set(on: dest.path)
                            fixed = true
                            resolved = dest.resolvingSymlinksInPath()
                        }
                        findings.append(.init(kind: .brokenLink, skillId: skillId, targetKey: key, path: target.path,
                                              message: "Broken symlink (destination does not exist)" + (fixed ? " — re-linked" : ""),
                                              fixable: storeOK, fixed: fixed))
                    } else if linkDestination == nil {
                        findings.append(.init(kind: .userShadow, skillId: skillId, targetKey: key, path: target.path,
                                              message: "The lockfile records a symlink, but on disk it is a regular file or directory — the user may have replaced it",
                                              fixable: false, fixed: false))
                    }
                case .copy:
                    if let drift = CopySync.drift(at: dest), !drift.isEmpty {
                        var fixed = false
                        var fixNote = ""
                        if fix && storeOK {
                            do {
                                try CopySync.copy(from: store.currentLink(ref), to: dest,
                                                  skillId: skillId, version: entry.version)
                                fixed = true
                            } catch {
                                fixNote = " — fix FAILED: \(error)"
                            }
                        }
                        let detail = "\(drift.changed.count) changed, \(drift.added.count) added, \(drift.missing.count) missing files"
                        findings.append(.init(kind: .copyDrift, skillId: skillId, targetKey: key, path: target.path,
                                              message: "Copy drifted from its manifest (\(detail))" + (fixed ? " — re-copied, OVERWRITING manual edits" : fixNote),
                                              fixable: storeOK, fixed: fixed))
                    } else if CopySync.readManifest(at: dest) == nil {
                        findings.append(.init(kind: .userShadow, skillId: skillId, targetKey: key, path: target.path,
                                              message: "Missing .ageos-manifest.json — the copy may have been replaced by hand",
                                              fixable: false, fixed: false))
                    }
                }
            }
        }

        // 2) Orphans: files carrying the AgeOS marker inside an agent folder that the lockfile does not know.
        // Compared through canonicalPath — /var vs /private/var once made every valid entry
        // look like an orphan, and --fix deleted them.
        let knownPaths = Set(lock.skills.values.flatMap { $0.targets.values.map { $0.path.canonicalFilePath } })
        for adapter in adapters.detected() {
            guard let skillsBlock = adapter.skills else { continue }
            let dir = AgeOSHome.expand(skillsBlock.globalPath)
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles]) else {
                if !fm.fileExists(atPath: dir.path) && lockReferencesAdapter(lock, adapter.id) {
                    findings.append(.init(kind: .agentPathMissing, skillId: nil, targetKey: nil, path: dir.path,
                                          message: "The skills directory for '\(adapter.id)' disappeared, but the lockfile still has entries",
                                          fixable: false, fixed: false))
                }
                continue
            }
            for entry in entries {
                let managed = ManagedMarker.isSet(on: entry.path) || CopySync.readManifest(at: entry) != nil
                if managed && !knownPaths.contains(entry.canonicalPath) {
                    var fixed = false
                    if fix {
                        try? fm.removeItem(at: entry)
                        fixed = true
                    }
                    findings.append(.init(kind: .orphanFile, skillId: nil, targetKey: nil, path: entry.path,
                                          message: "File created by AgeOS with no matching lockfile entry (orphan)" + (fixed ? " — removed" : ""),
                                          fixable: true, fixed: fixed))
                }
            }
        }

        return findings
    }

    func lockReferencesAdapter(_ lock: Lockfile, _ adapterId: String) -> Bool {
        lock.skills.values.contains { $0.targets.keys.contains { $0.hasPrefix("\(adapterId)@") } }
    }
}
