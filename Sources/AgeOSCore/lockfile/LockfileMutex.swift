import Foundation

/// A cross-process lock around the lockfile's read-modify-write cycle.
/// The `ageos` CLI and the long-running `ageos-mcp` run side by side by design — without
/// flock they load the same snapshot, whoever writes last erases the other's update, and
/// the orphaned entry that leaves behind gets deleted by `doctor --fix` in a chain reaction.
public enum LockfileMutex {
    /// An exclusive flock(2) on the `.ageos.flock` file next to the lockfile. Reentrancy:
    /// deliberately NOT reentrant within one process, for simplicity — each public operation
    /// on LinkEngine or McpManager wraps itself exactly once and they never nest.
    public static func withExclusiveLock<T>(home: AgeOSHome, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: home.root, withIntermediateDirectories: true)
        let lockPath = home.root.appendingPathComponent(".ageos.flock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            throw AgeOSError(.storeCorrupt, "Cannot open lock file \(lockPath): \(String(cString: strerror(errno)))",
                             remedy: "Check write permission on \(home.root.path)")
        }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else {
            throw AgeOSError(.conflict, "Cannot acquire the lockfile lock: \(String(cString: strerror(errno)))",
                             remedy: "Another ageos process may be stuck — try again")
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
