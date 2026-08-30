import Foundation

/// Store content-addressed theo version:
/// `library/skills/<ns>/<name>/<version>/` plus a `current` symlink → the version in use.
///
/// Because every adapter links to `current`, swapping a version is one atomic symlink change
/// → every symlinked target follows the new build at once, with no per-agent work.
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

    /// The `current` symlink — LinkEngine always points here, never at a specific version.
    public func currentLink(_ ref: SkillRef) -> URL {
        skillDir(ref).appendingPathComponent("current")
    }

    /// Installs a version from a staging directory (copy to a temp on the same volume, then rename — atomic).
    /// Idempotent: an already-present version is left alone (content-addressed).
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
            // Two processes installing at once: the other one winning is also success.
            if fm.fileExists(atPath: dest.path) { return dest }
            throw error
        }
        return dest
    }

    /// Points `current` at a version (a relative symlink, so the store stays movable).
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

    /// Every skill present in the store (found by following `current` symlinks — the filesystem is the truth).
    public func listInstalled() -> [(ref: SkillRef, version: String)] {
        var result: [(SkillRef, String)] = []
        // Resolve both sides before comparing prefixes: the enumerator returns resolved paths
        // (/private/var/...) while root may still be in symlink form (/var/...).
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

    /// Removes orphaned versions: not `current`, and not listed in `keep`.
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

    /// Removes a skill from the store entirely (every version plus current).
    public func remove(_ ref: SkillRef) throws {
        let dir = skillDir(ref)
        guard fm.fileExists(atPath: dir.path) else { return }
        try fm.removeItem(at: dir)
    }

    /// The version doubles as a directory name — reject odd characters (path traversal, `/`),
    /// strip ".." and a leading dot (so the enumerator does not skip it as a hidden directory).
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
