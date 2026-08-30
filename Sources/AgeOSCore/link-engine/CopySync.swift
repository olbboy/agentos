import Foundation
import CryptoKit

/// Copy mode for agents that ignore symlinks (codex): copy the files plus a per-file hash
/// manifest, so we can (1) re-sync when a version changes and (2) detect hand edits without overwriting them.
public enum CopySync {
    public static let manifestName = ".ageos-manifest.json"
    static let ignoredFiles: Set<String> = [manifestName, ".DS_Store"]

    public struct Manifest: Sendable, Codable, Equatable {
        public var skillId: String
        public var version: String
        /// relative path → sha256 hex.
        public var files: [String: String]
    }

    public struct Drift: Sendable, Equatable {
        public var changed: [String]
        public var missing: [String]
        public var added: [String]
        public var isEmpty: Bool { changed.isEmpty && missing.isEmpty && added.isEmpty }
    }

    public static func hashFiles(in dir: URL) -> [String: String] {
        var result: [String: String] = [:]
        let base = dir.resolvingSymlinksInPath()
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return result
        }
        for case let url as URL in walker {
            let resolved = url.resolvingSymlinksInPath()
            guard (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let rel = String(resolved.path.dropFirst(base.path.count + 1))
            guard !ignoredFiles.contains((rel as NSString).lastPathComponent) else { continue }
            if let data = FileManager.default.contents(atPath: resolved.path) {
                result[rel] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
        }
        return result
    }

    /// Copies the skill's contents into `destination` (replacing it if present), writing the manifest and marker.
    public static func copy(from source: URL, to destination: URL, skillId: String, version: String) throws {
        let fm = FileManager.default
        let resolvedSource = source.resolvingSymlinksInPath()
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let tmp = parent.appendingPathComponent(".\(destination.lastPathComponent).copy-\(UUID().uuidString.prefix(8))")
        try fm.copyItem(at: resolvedSource, to: tmp)

        let manifest = Manifest(skillId: skillId, version: version, files: hashFiles(in: tmp))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: tmp.appendingPathComponent(manifestName))

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tmp, to: destination)
        ManagedMarker.set(on: destination.path)
    }

    public static func readManifest(at dir: URL) -> Manifest? {
        guard let data = FileManager.default.contents(atPath: dir.appendingPathComponent(manifestName).path) else {
            return nil
        }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    /// Compares what is on disk against the manifest — any difference means the user edited it.
    public static func drift(at dir: URL) -> Drift? {
        guard let manifest = readManifest(at: dir) else { return nil }
        let current = hashFiles(in: dir)
        var changed: [String] = [], missing: [String] = [], added: [String] = []
        for (path, hash) in manifest.files {
            switch current[path] {
            case nil: missing.append(path)
            case let h? where h != hash: changed.append(path)
            default: break
            }
        }
        for path in current.keys where manifest.files[path] == nil {
            added.append(path)
        }
        return Drift(changed: changed.sorted(), missing: missing.sorted(), added: added.sorted())
    }
}
