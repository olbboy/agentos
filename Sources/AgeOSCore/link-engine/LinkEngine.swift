import Foundation
import CryptoKit

/// Enable/disable skill vào thư mục agent theo adapter spec.
/// Bất biến an toàn:
/// 1. Không bao giờ ghi đè thứ AgeOS không tạo (nhận diện: lockfile + xattr marker).
/// 2. Idempotent — enable lại chỉ refresh link/copy của chính mình.
/// 3. Symlink trỏ vào `current` của store → swap version lan tự động; copy mode
///    được `propagateVersionChange` sync lại (tôn trọng drift).
public struct LinkEngine: Sendable {
    public let home: AgeOSHome
    public let store: Store
    public let adapters: AdapterRegistry

    public init(home: AgeOSHome, store: Store, adapters: AdapterRegistry) {
        self.home = home
        self.store = store
        self.adapters = adapters
    }

    public struct TargetOutcome: Sendable, Codable {
        public var skillId: String
        public var adapterId: String
        public var scope: String
        public var mode: String
        public var path: String
        public var note: String?
    }

    // MARK: - Enable

    public func enable(_ ref: SkillRef, sourceId: String, adapterId: String,
                       project: URL? = nil, modeOverride: AdapterSpec.LinkModeSpec? = nil) throws -> TargetOutcome {
        try LockfileMutex.withExclusiveLock(home: home) {
            try enableLocked(ref, sourceId: sourceId, adapterId: adapterId,
                             project: project, modeOverride: modeOverride)
        }
    }

    private func enableLocked(_ ref: SkillRef, sourceId: String, adapterId: String,
                              project: URL?, modeOverride: AdapterSpec.LinkModeSpec?) throws -> TargetOutcome {
        let adapter = try adapters.adapter(id: adapterId)
        guard let skillsBlock = adapter.skills else {
            throw AgeOSError(.unsupported, "Adapter '\(adapterId)' không hỗ trợ skills (mcp-only)",
                             remedy: "Dùng adapter khác — xem `ageos targets list`")
        }
        guard let version = store.currentVersion(ref) else {
            throw AgeOSError(.notFound, "Skill \(ref.id) chưa có trong store",
                             remedy: "Chạy `ageos sync` trước khi enable")
        }

        var mode = modeOverride ?? adapter.effectiveSkillMode
        if mode == .symlink && !skillsBlock.folderSymlink {
            if modeOverride == .symlink {
                throw AgeOSError(.unsupported, "Agent '\(adapterId)' không discover folder-symlink (đo thực nghiệm)",
                                 remedy: "Bỏ --mode symlink để dùng copy mode")
            }
            mode = .copy
        }

        let destDir: URL
        let scope: String
        if let project {
            guard let projectPath = skillsBlock.projectPath else {
                throw AgeOSError(.unsupported, "Adapter '\(adapterId)' không khai báo projectPath",
                                 remedy: "Enable global (bỏ --project) hoặc bổ sung projectPath vào adapter JSON")
            }
            destDir = project.appendingPathComponent(projectPath, isDirectory: true)
            scope = "project"
        } else {
            destDir = AgeOSHome.expand(skillsBlock.globalPath)
            scope = "global"
        }
        let dest = destDir.appendingPathComponent(ref.name)

        var lock = try Lockfile.load(from: home.lockfilePath)
        let key = Lockfile.targetKey(adapter: adapterId, projectPath: project?.path)

        // Preflight: đích đã có thứ gì đó → chỉ đi tiếp nếu là của mình.
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let destExists = fm.fileExists(atPath: dest.path, isDirectory: &isDir)
            || (try? fm.destinationOfSymbolicLink(atPath: dest.path)) != nil
        if destExists && !isOurs(dest) {
            throw AgeOSError(.conflict, "Đã tồn tại '\(ref.name)' tại \(destDir.path) KHÔNG do AgeOS quản lý",
                             remedy: "Đổi tên/xóa bản thủ công đó nếu muốn AgeOS quản lý, hoặc giữ nguyên — AgeOS không ghi đè đồ user")
        }

        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        switch mode {
        case .symlink:
            if destExists { try fm.removeItem(at: dest) }
            try fm.createSymbolicLink(atPath: dest.path, withDestinationPath: store.currentLink(ref).path)
            ManagedMarker.set(on: dest.path)
        case .copy:
            try CopySync.copy(from: store.currentLink(ref), to: dest, skillId: ref.id, version: version)
        }

        var entry = lock.skills[ref.id] ?? .init(source: sourceId, version: version)
        entry.version = version
        entry.source = sourceId
        entry.targets[key] = .init(scope: scope, linkMode: mode == .symlink ? .symlink : .copy,
                                   path: dest.path,
                                   manifestSha256: mode == .copy ? CopySync.readManifest(at: dest).map(hashOfManifest) : nil)
        lock.skills[ref.id] = entry
        try lock.save(to: home.lockfilePath)

        let note = skillsBlock.verified ? nil : "adapter '\(adapterId)' chưa verified trên máy thật — chạy `ageos doctor` sau khi thử"
        return TargetOutcome(skillId: ref.id, adapterId: adapterId, scope: scope,
                             mode: mode.rawValue, path: dest.path, note: note)
    }

    // MARK: - Disable

    public func disable(_ ref: SkillRef, adapterId: String, project: URL? = nil) throws -> TargetOutcome {
        try LockfileMutex.withExclusiveLock(home: home) {
            try disableLocked(ref, adapterId: adapterId, project: project)
        }
    }

    private func disableLocked(_ ref: SkillRef, adapterId: String, project: URL?) throws -> TargetOutcome {
        var lock = try Lockfile.load(from: home.lockfilePath)
        let key = Lockfile.targetKey(adapter: adapterId, projectPath: project?.path)

        guard var entry = lock.skills[ref.id], let target = entry.targets[key] else {
            throw AgeOSError(.notFound, "\(ref.id) chưa enable cho '\(key)' theo lockfile",
                             remedy: "Xem trạng thái bằng `ageos doctor`; nếu file tồn tại ngoài lockfile thì đó là orphan — `ageos doctor --fix` sẽ dọn")
        }

        let dest = URL(fileURLWithPath: target.path)
        let fm = FileManager.default
        let destExists = fm.fileExists(atPath: dest.path)
            || (try? fm.destinationOfSymbolicLink(atPath: dest.path)) != nil
        if destExists {
            guard isOurs(dest) else {
                throw AgeOSError(.conflict, "File tại \(dest.path) không phải do AgeOS tạo — không gỡ",
                                 remedy: "Kiểm tra thủ công; có thể user đã thay bản của AgeOS bằng bản riêng")
            }
            try fm.removeItem(at: dest)
        }

        entry.targets.removeValue(forKey: key)
        if entry.targets.isEmpty {
            lock.skills.removeValue(forKey: ref.id)
        } else {
            lock.skills[ref.id] = entry
        }
        try lock.save(to: home.lockfilePath)

        return TargetOutcome(skillId: ref.id, adapterId: adapterId,
                             scope: target.scope, mode: target.linkMode.rawValue, path: dest.path,
                             note: destExists ? nil : "đích đã biến mất từ trước — chỉ dọn lockfile")
    }

    // MARK: - Version propagation (gọi sau sync đổi version)

    public struct PropagationReport: Sendable, Codable {
        public var skillId: String
        public var resynced: [String]
        public var driftSkipped: [String]
    }

    public func propagateVersionChange(_ ref: SkillRef, newVersion: String, force: Bool = false) throws -> PropagationReport? {
        try LockfileMutex.withExclusiveLock(home: home) {
            try propagateVersionChangeLocked(ref, newVersion: newVersion, force: force)
        }
    }

    private func propagateVersionChangeLocked(_ ref: SkillRef, newVersion: String, force: Bool) throws -> PropagationReport? {
        var lock = try Lockfile.load(from: home.lockfilePath)
        guard var entry = lock.skills[ref.id] else { return nil }
        var resynced: [String] = []
        var skipped: [String] = []

        for (key, target) in entry.targets {
            switch target.linkMode {
            case .config:
                continue // entry MCP — version skill không liên quan
            case .symlink:
                resynced.append(key) // symlink ăn theo `current` — không cần làm gì
            case .copy:
                let dest = URL(fileURLWithPath: target.path)
                // Đích tồn tại mà KHÔNG còn manifest AgeOS = user đã thay bằng đồ riêng
                // → tuyệt đối không re-copy đè (cùng lớp bug với isOurs hằng-đúng).
                if FileManager.default.fileExists(atPath: dest.path),
                   CopySync.readManifest(at: dest) == nil {
                    skipped.append("\(key): đích mất manifest AgeOS (user đã thay?) — bỏ qua, kiểm tra bằng `ageos doctor`")
                    continue
                }
                if let drift = CopySync.drift(at: dest), !drift.isEmpty, !force {
                    skipped.append("\(key): user đã sửa tay (\(drift.changed.count) đổi, \(drift.added.count) thêm, \(drift.missing.count) mất)")
                    continue
                }
                try CopySync.copy(from: store.currentLink(ref), to: dest, skillId: ref.id, version: newVersion)
                var updated = target
                updated.manifestSha256 = CopySync.readManifest(at: dest).map(hashOfManifest)
                entry.targets[key] = updated
                resynced.append(key)
            }
        }
        entry.version = newVersion
        lock.skills[ref.id] = entry
        try lock.save(to: home.lockfilePath)
        return PropagationReport(skillId: ref.id, resynced: resynced.sorted(), driftSkipped: skipped.sorted())
    }

    // MARK: - Helpers

    /// "Của mình" CHỈ theo bằng chứng vật lý trên đích: xattr marker, manifest AgeOS,
    /// hoặc symlink trỏ vào store của AgeOS. TUYỆT ĐỐI không so path lockfile với
    /// dest — dest thường được DỰNG TỪ chính path đó (hằng-đúng, từng là lỗ hổng
    /// Critical khiến disable xóa nhầm thư mục user thay chỗ symlink của AgeOS).
    func isOurs(_ dest: URL) -> Bool {
        if ManagedMarker.isSet(on: dest.path) { return true }
        if CopySync.readManifest(at: dest) != nil { return true }
        if let linkTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: dest.path) {
            // Symlink của AgeOS luôn trỏ vào library store (tạo bằng path tuyệt đối,
            // nhưng chấp nhận cả relative để bền với chỉnh tay vô hại).
            let resolved = linkTarget.hasPrefix("/")
                ? URL(fileURLWithPath: linkTarget)
                : dest.deletingLastPathComponent().appendingPathComponent(linkTarget)
            if resolved.canonicalPath.hasPrefix(home.skillsLibraryDir.canonicalPath + "/") {
                return true
            }
        }
        return false
    }

    /// Hash gọn toàn manifest — lockfile chỉ cần 1 giá trị so nhanh.
    func hashOfManifest(_ manifest: CopySync.Manifest) -> String {
        let joined = manifest.files.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
