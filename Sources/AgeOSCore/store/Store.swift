import Foundation

/// Store content-addressed theo version:
/// `library/skills/<ns>/<name>/<version>/` + symlink `current` → version đang dùng.
///
/// Vì mọi adapter link vào `current`, swap version = 1 lần thay symlink atomic
/// → mọi target symlink "ăn theo" bản mới ngay, không cần đụng từng agent.
public struct Store: Sendable {
    public let home: AgeOSHome
    private var fm: FileManager { .default }

    public init(home: AgeOSHome) {
        self.home = home
    }

    public func skillDir(_ ref: SkillRef) -> URL {
        ref.pathComponents.reduce(home.skillsLibraryDir) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    public func versionDir(_ ref: SkillRef, version: String) -> URL {
        skillDir(ref).appendingPathComponent(safeVersion(version), isDirectory: true)
    }

    /// Symlink `current` — LinkEngine (Phase 3) luôn trỏ vào đây, không trỏ version cụ thể.
    public func currentLink(_ ref: SkillRef) -> URL {
        skillDir(ref).appendingPathComponent("current")
    }

    /// Cài một version từ thư mục staging (copy vào tmp cùng volume rồi rename — atomic).
    /// Idempotent: version đã tồn tại thì giữ nguyên (content-addressed).
    @discardableResult
    public func installVersion(_ ref: SkillRef, version: String, from staging: URL) throws -> URL {
        let dest = versionDir(ref, version: version)
        if fm.fileExists(atPath: dest.path) { return dest }
        let parent = dest.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let tmp = parent.appendingPathComponent(".staging-\(UUID().uuidString.prefix(8))")
        try fm.copyItem(at: staging, to: tmp)
        do {
            try fm.moveItem(at: tmp, to: dest)
        } catch {
            _ = try? fm.removeItem(at: tmp)
            // Race hai tiến trình cùng cài: bên kia thắng cũng là thành công.
            if fm.fileExists(atPath: dest.path) { return dest }
            throw error
        }
        return dest
    }

    /// Trỏ `current` sang version (symlink tương đối để store di chuyển được).
    public func setCurrent(_ ref: SkillRef, version: String) throws {
        let dest = versionDir(ref, version: version)
        guard fm.fileExists(atPath: dest.path) else {
            throw AgeOSError(.notFound, "Version \(version) of \(ref.id) is not installed in the store",
                             remedy: "Run `ageos sync` first")
        }
        try AtomicFile.replaceSymlink(at: currentLink(ref), target: safeVersion(version))
    }

    public func currentVersion(_ ref: SkillRef) -> String? {
        try? fm.destinationOfSymbolicLink(atPath: currentLink(ref).path)
    }

    public func installedVersions(_ ref: SkillRef) -> [String] {
        let dir = skillDir(ref)
        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        return entries.filter { $0 != "current" && !$0.hasPrefix(".") }.sorted()
    }

    /// Mọi skill có mặt trong store (dò symlink `current` — nguồn chân lý là filesystem).
    public func listInstalled() -> [(ref: SkillRef, version: String)] {
        var result: [(SkillRef, String)] = []
        // Resolve cả hai phía trước khi so prefix: enumerator trả path đã resolve
        // (/private/var/...) trong khi root có thể là dạng symlink (/var/...).
        let root = home.skillsLibraryDir.resolvingSymlinksInPath()
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                         options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in walker {
            guard url.lastPathComponent == "current",
                  let target = try? fm.destinationOfSymbolicLink(atPath: url.path) else { continue }
            let skillPath = url.deletingLastPathComponent().resolvingSymlinksInPath().path
            guard skillPath.hasPrefix(root.path + "/") else { continue }
            let rel = String(skillPath.dropFirst(root.path.count + 1))
            if let ref = SkillRef(id: rel) {
                result.append((ref, target))
                walker.skipDescendants()
            }
        }
        return result.sorted { $0.0.id < $1.0.id }
    }

    /// Xóa version mồ côi: không phải `current` và không nằm trong `keep`.
    @discardableResult
    public func gcOrphans(_ ref: SkillRef, keep: Set<String> = []) throws -> [String] {
        let current = currentVersion(ref)
        var removed: [String] = []
        for v in installedVersions(ref) where v != current && !keep.contains(v) {
            try fm.removeItem(at: versionDir(ref, version: v))
            removed.append(v)
        }
        return removed
    }

    /// Gỡ hẳn skill khỏi store (mọi version + current).
    public func remove(_ ref: SkillRef) throws {
        let dir = skillDir(ref)
        guard fm.fileExists(atPath: dir.path) else { return }
        try fm.removeItem(at: dir)
    }

    /// Version dùng làm tên thư mục — chặn ký tự lạ (path traversal, `/`),
    /// gọt chuỗi ".." và dấu chấm đầu (tránh hidden dir bị enumerator bỏ qua).
    private func safeVersion(_ version: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: ".-_"))
        var cleaned = String(version.unicodeScalars.filter { allowed.contains($0) })
        while cleaned.contains("..") {
            cleaned = cleaned.replacingOccurrences(of: "..", with: ".")
        }
        cleaned = String(cleaned.drop(while: { $0 == "." }))
        cleaned = String(cleaned.prefix(64))
        return cleaned.isEmpty ? "unknown" : cleaned
    }
}
