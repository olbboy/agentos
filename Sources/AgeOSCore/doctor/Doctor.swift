import Foundation

/// Khám drift giữa lockfile ↔ filesystem thật, sửa được với `--fix`:
/// link gãy → re-link · copy drift → re-copy (chỉ khi --fix, in rõ) ·
/// orphan file (marker AgeOS nhưng lockfile không biết) → gỡ ·
/// đích biến mất → tái tạo · agent path biến mất → cảnh báo.
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

        // 1) Đối chiếu từng entry lockfile với filesystem.
        for (skillId, entry) in lock.skills.sorted(by: { $0.key < $1.key }) {
            guard let ref = SkillRef(id: skillId) else { continue }
            let storeOK = store.currentVersion(ref) != nil
            if !storeOK {
                findings.append(.init(kind: .storeMissing, skillId: skillId, targetKey: nil,
                                      path: store.skillDir(ref).path,
                                      message: "Skill mất khỏi store nhưng lockfile còn — chạy `ageos sync` để tải lại",
                                      fixable: false, fixed: false))
            }

            for (key, target) in entry.targets.sorted(by: { $0.key < $1.key }) {
                let parts = key.split(separator: "@", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let adapterId = parts[0]
                let projectPath: String? = parts[1] == "global" ? nil : parts[1]
                guard (try? adapters.adapter(id: adapterId)) != nil else {
                    findings.append(.init(kind: .adapterUnknown, skillId: skillId, targetKey: key, path: target.path,
                                          message: "Adapter '\(adapterId)' không còn trong registry",
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
                            fixNote = " — fix THẤT BẠI: \(error)"
                        }
                    }
                    findings.append(.init(kind: .missingTarget, skillId: skillId, targetKey: key, path: target.path,
                                          message: "Đích enable biến mất" + (fixed ? " — đã tái tạo" : fixNote),
                                          fixable: storeOK, fixed: fixed))
                    continue
                }

                switch target.linkMode {
                case .config:
                    break // entry MCP trong config client — Phase 4 disable/enable tự quản, doctor skill không đụng
                case .symlink:
                    // Link tồn tại nhưng đích chết (store dời/mất) → re-link.
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
                                              message: "Symlink gãy (đích không tồn tại)" + (fixed ? " — đã re-link" : ""),
                                              fixable: storeOK, fixed: fixed))
                    } else if linkDestination == nil {
                        findings.append(.init(kind: .userShadow, skillId: skillId, targetKey: key, path: target.path,
                                              message: "Lockfile ghi symlink nhưng trên đĩa là file/thư mục thường — có thể user đã thay",
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
                                fixNote = " — fix THẤT BẠI: \(error)"
                            }
                        }
                        let detail = "đổi \(drift.changed.count), thêm \(drift.added.count), mất \(drift.missing.count) file"
                        findings.append(.init(kind: .copyDrift, skillId: skillId, targetKey: key, path: target.path,
                                              message: "Copy lệch manifest (\(detail))" + (fixed ? " — đã re-copy ĐÈ chỉnh sửa tay" : fixNote),
                                              fixable: storeOK, fixed: fixed))
                    } else if CopySync.readManifest(at: dest) == nil {
                        findings.append(.init(kind: .userShadow, skillId: skillId, targetKey: key, path: target.path,
                                              message: "Thiếu .ageos-manifest.json — bản copy có thể đã bị thay thủ công",
                                              fixable: false, fixed: false))
                    }
                }
            }
        }

        // 2) Orphan: file mang marker AgeOS trong thư mục agent nhưng lockfile không biết.
        // So sánh qua canonicalPath — /var vs /private/var từng làm mọi entry hợp lệ
        // bị coi là orphan và bị --fix xóa nhầm.
        let knownPaths = Set(lock.skills.values.flatMap { $0.targets.values.map { $0.path.canonicalFilePath } })
        for adapter in adapters.detected() {
            guard let skillsBlock = adapter.skills else { continue }
            let dir = AgeOSHome.expand(skillsBlock.globalPath)
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles]) else {
                if !fm.fileExists(atPath: dir.path) && lockReferencesAdapter(lock, adapter.id) {
                    findings.append(.init(kind: .agentPathMissing, skillId: nil, targetKey: nil, path: dir.path,
                                          message: "Thư mục skills của '\(adapter.id)' biến mất dù lockfile còn entry",
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
                                          message: "File AgeOS tạo nhưng lockfile không còn entry (orphan)" + (fixed ? " — đã gỡ" : ""),
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
