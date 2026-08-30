import Foundation

/// macOS có prefix symlink hệ thống (`/var` → `/private/var`, `/tmp` → `/private/tmp`)
/// nên hai path cùng trỏ một file có thể khác chuỗi. MỌI phép so sánh path trong
/// AgeOS phải đi qua `canonicalPath` — so chuỗi thô là bug đang chờ nổ.
extension URL {
    var canonicalPath: String {
        resolvingSymlinksInPath().path
    }
}

extension String {
    /// Canonical hóa một path string (expand `~`, resolve symlink prefix).
    var canonicalFilePath: String {
        URL(fileURLWithPath: (self as NSString).expandingTildeInPath).canonicalPath
    }
}
