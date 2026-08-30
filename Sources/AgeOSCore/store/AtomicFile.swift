import Foundation

/// Ghi file/thư mục theo kiểu atomic: ghi vào tên tạm cùng volume rồi `rename(2)`.
/// Rename cùng volume là atomic ở tầng POSIX — reader không bao giờ thấy trạng thái dở dang.
public enum AtomicFile {
    /// Ghi data vào `destination` atomically.
    public static func write(_ data: Data, to destination: URL) throws {
        let dir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString.prefix(8))")
        try data.write(to: tmp)
        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
    }

    /// Thay thế (hoặc tạo) symlink tại `linkURL` trỏ tới `target` một cách atomic.
    public static func replaceSymlink(at linkURL: URL, target: String) throws {
        let dir = linkURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(linkURL.lastPathComponent).lnk-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createSymbolicLink(atPath: tmp.path, withDestinationPath: target)
        // rename(2) đè symlink cũ atomically; moveItem của FileManager từ chối đè nên dùng syscall.
        guard rename(tmp.path, linkURL.path) == 0 else {
            let err = String(cString: strerror(errno))
            _ = try? FileManager.default.removeItem(at: tmp)
            throw AgeOSError(.storeCorrupt, "Không thay được symlink \(linkURL.path): \(err)",
                             remedy: "Kiểm tra quyền ghi thư mục \(dir.path)")
        }
    }

    /// Di chuyển cả thư mục vào vị trí đích atomically (đích không được tồn tại trước).
    public static func moveDirectory(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
