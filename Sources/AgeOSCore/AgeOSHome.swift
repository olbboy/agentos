import Foundation

/// Layout thư mục gốc `~/.ageos/`. Mọi path đi qua đây; test đặt `AGEOS_HOME`
/// để không đụng home thật — vì vậy KHÔNG bao giờ hardcode `~` ở nơi khác.
public struct AgeOSHome: Sendable {
    public let root: URL

    /// Thứ tự ưu tiên: tham số tường minh > env `AGEOS_HOME` > `~/.ageos`.
    public init(root: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let root {
            self.root = root
        } else if let env = environment["AGEOS_HOME"], !env.isEmpty {
            self.root = URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            self.root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ageos", isDirectory: true)
        }
    }

    public var libraryDir: URL { root.appendingPathComponent("library", isDirectory: true) }
    public var skillsLibraryDir: URL { libraryDir.appendingPathComponent("skills", isDirectory: true) }
    public var mcpLibraryDir: URL { libraryDir.appendingPathComponent("mcp", isDirectory: true) }
    public var backupsDir: URL { root.appendingPathComponent("backups", isDirectory: true) }
    public var adaptersDir: URL { root.appendingPathComponent("adapters", isDirectory: true) }
    public var cacheDir: URL { root.appendingPathComponent("cache", isDirectory: true) }
    public var indexPath: URL { root.appendingPathComponent("index.sqlite") }
    public var sourcesPath: URL { root.appendingPathComponent("sources.json") }
    public var lockfilePath: URL { root.appendingPathComponent("ageos.lock.json") }

    /// Tạo đủ cây thư mục (idempotent).
    public func ensureLayout() throws {
        for dir in [root, libraryDir, skillsLibraryDir, mcpLibraryDir, backupsDir, adaptersDir, cacheDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Expand path dạng `~/...` hoặc tuyệt đối thành URL (dùng cho adapter spec).
    public static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}
