import Foundation

/// Đánh dấu "AgeOS tạo ra" bằng xattr `dev.ageos.managed` — lớp phụ bên cạnh lockfile
/// (lockfile là nguồn chính; xattr sống sót khi lockfile mất, và ngược lại khi backup
/// tool strip xattr thì lockfile vẫn còn — hai lớp bù nhau).
public enum ManagedMarker {
    public static let attrName = "dev.ageos.managed"

    /// Đặt marker. `followSymlink: false` → đánh dấu chính symlink (không phải đích).
    public static func set(on path: String, followSymlink: Bool = false) {
        let options: Int32 = followSymlink ? 0 : XATTR_NOFOLLOW
        "1".withCString { value in
            _ = setxattr(path, attrName, value, 1, 0, options)
        }
    }

    public static func isSet(on path: String, followSymlink: Bool = false) -> Bool {
        let options: Int32 = followSymlink ? 0 : XATTR_NOFOLLOW
        return getxattr(path, attrName, nil, 0, 0, options) >= 0
    }

    public static func remove(on path: String, followSymlink: Bool = false) {
        let options: Int32 = followSymlink ? 0 : XATTR_NOFOLLOW
        _ = removexattr(path, attrName, options)
    }
}
