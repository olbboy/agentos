import Foundation

/// macOS has system symlink prefixes (`/var` → `/private/var`, `/tmp` → `/private/tmp`), so
/// two paths pointing at the same file can be different strings. EVERY path comparison in
/// AgeOS must go through `canonicalPath` — comparing raw strings is a bug waiting to happen.
extension URL {
    var canonicalPath: String {
        resolvingSymlinksInPath().path
    }
}

extension String {
    /// Canonicalizes a path string (expands `~`, resolves symlink prefixes).
    var canonicalFilePath: String {
        URL(fileURLWithPath: (self as NSString).expandingTildeInPath).canonicalPath
    }
}
