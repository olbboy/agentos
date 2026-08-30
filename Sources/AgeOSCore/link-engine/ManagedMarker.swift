import Foundation

/// Marks something as "created by AgeOS" with the `dev.ageos.managed` xattr — a second
/// layer beside the lockfile. The lockfile is primary; the xattr survives a lost lockfile,
/// and when a backup tool strips xattrs the lockfile still holds. The two cover each other.
public enum ManagedMarker {
    public static let attrName = "dev.ageos.managed"

    /// Sets the marker. `followSymlink: false` → mark the symlink itself, not its destination.
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
