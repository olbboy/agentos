import Foundation

/// The contract for writing a client config. Safety invariants every writer MUST keep:
/// 1. NEVER regenerate the whole file — only parse-merge our own entry.
/// 2. Unknown keys and the user's own entries survive untouched.
/// 3. An already-malformed file → REFUSE to write, and point at the error (do no further damage).
/// 4. Write atomically; the backup is taken by McpManager BEFORE the writer is called.
public protocol ConfigWriter: Sendable {
    /// Adds or updates the entry `name` under keyPath. Creates the file if it does not exist.
    func upsertEntry(name: String, launch: McpServerModel.Launch, keyPath: String, in file: URL) throws
    /// Removes the entry `name`. Not an error if it is absent (idempotent).
    func removeEntry(name: String, keyPath: String, in file: URL) throws
    /// Whether the entry `name` exists (a missing file means false).
    func hasEntry(name: String, keyPath: String, in file: URL) throws -> Bool
}

/// Backs a client config up into `~/.ageos/backups/<timestamp>/` before EVERY write.
public enum ConfigBackup {
    static let stampFormat: Date.ISO8601FormatStyle = .iso8601

    /// Returns the backup URL (nil when the original does not exist — nothing to back up).
    /// A backup NEVER overwrites an older one: stamped to the millisecond, plus a suffix if
    /// that still collides (two operations in the same second once made restore pick the wrong file).
    @discardableResult
    public static func backup(_ file: URL, home: AgeOSHome) throws -> URL? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
            .replacingOccurrences(of: ":", with: "-")
        let dir = home.backupsDir.appendingPathComponent(stamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // The full path is encoded into the filename so restore knows where it came from.
        let encoded = file.path.replacingOccurrences(of: "/", with: "%2F")
        var dest = dir.appendingPathComponent(encoded)
        var suffix = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            suffix += 1
            dest = dir.appendingPathComponent("\(encoded).\(suffix)")
        }
        try FileManager.default.copyItem(at: file, to: dest)
        return dest
    }

    public struct BackupRecord: Sendable, Codable {
        public var timestamp: String
        public var originalPath: String
        public var backupPath: String
    }

    public static func list(home: AgeOSHome) -> [BackupRecord] {
        let fm = FileManager.default
        guard let stamps = try? fm.contentsOfDirectory(atPath: home.backupsDir.path) else { return [] }
        var records: [BackupRecord] = []
        for stamp in stamps.sorted() {
            let dir = home.backupsDir.appendingPathComponent(stamp, isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for f in files.sorted() {
                // Strip the anti-collision `.N` suffix, if any, before decoding the original path.
                let base = f.replacingOccurrences(of: #"\.\d+$"#, with: "", options: .regularExpression)
                let original = base.replacingOccurrences(of: "%2F", with: "/")
                records.append(.init(timestamp: stamp, originalPath: original,
                                     backupPath: dir.appendingPathComponent(f).path))
            }
        }
        return records
    }

    /// Restores the MOST RECENT backup of one file (`original == nil` is an error — it must be named).
    public static func restoreLatest(of original: URL, home: AgeOSHome) throws -> BackupRecord {
        let matches = list(home: home).filter { $0.originalPath == original.path }
        guard let latest = matches.last else {
            throw AgeOSError(.notFound, "No backup exists for \(original.path)",
                             remedy: "List them with `ageos mcp restore-backup --list`")
        }
        // Back the current file up before overwriting it, so the revert can itself be reverted.
        _ = try? backup(original, home: home)
        let data = try Data(contentsOf: URL(fileURLWithPath: latest.backupPath))
        try AtomicFile.write(data, to: original)
        return latest
    }
}
