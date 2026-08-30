import Foundation

/// Writes files and directories atomically: write to a temporary name on the same volume,
/// then `rename(2)`. A same-volume rename is atomic at the POSIX level, so a reader never
/// sees a half-written state.
public enum AtomicFile {
    /// Writes data to `destination` atomically.
    public static func write(_ data: Data, to destination: URL) throws {
        let dir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString.prefix(8))")
        try data.write(to: tmp)
        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
    }

    /// Atomically replaces (or creates) the symlink at `linkURL`, pointing at `target`.
    public static func replaceSymlink(at linkURL: URL, target: String) throws {
        let dir = linkURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(linkURL.lastPathComponent).lnk-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createSymbolicLink(atPath: tmp.path, withDestinationPath: target)
        // rename(2) replaces the old symlink atomically; FileManager's moveItem refuses to overwrite, hence the syscall.
        guard rename(tmp.path, linkURL.path) == 0 else {
            let err = String(cString: strerror(errno))
            _ = try? FileManager.default.removeItem(at: tmp)
            throw AgeOSError(.storeCorrupt, "Cannot replace symlink \(linkURL.path): \(err)",
                             remedy: "Check write permission on \(dir.path)")
        }
    }

    /// Moves a whole directory into place atomically (the destination must not already exist).
    public static func moveDirectory(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
