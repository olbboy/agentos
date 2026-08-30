import Foundation

/// Khóa liên-tiến-trình cho chu trình read-modify-write lockfile.
/// `ageos` CLI và `ageos-mcp` (long-running) chạy song song theo thiết kế —
/// không flock thì hai bên load cùng snapshot, ai ghi sau đè mất update của
/// người trước, và entry "mồ côi" đó sẽ bị `doctor --fix` xóa nhầm dây chuyền.
public enum LockfileMutex {
    /// flock(2) exclusive trên file `.ageos.flock` cạnh lockfile. Reentrancy:
    /// KHÔNG reentrant trong cùng tiến trình theo thiết kế đơn giản — mỗi thao tác
    /// public của LinkEngine/McpManager tự bao đúng một lần, không lồng nhau.
    public static func withExclusiveLock<T>(home: AgeOSHome, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: home.root, withIntermediateDirectories: true)
        let lockPath = home.root.appendingPathComponent(".ageos.flock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            throw AgeOSError(.storeCorrupt, "Không mở được lock file \(lockPath): \(String(cString: strerror(errno)))",
                             remedy: "Kiểm tra quyền ghi thư mục \(home.root.path)")
        }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else {
            throw AgeOSError(.conflict, "Không lấy được khóa lockfile: \(String(cString: strerror(errno)))",
                             remedy: "Một tiến trình ageos khác có thể đang kẹt — thử lại")
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
