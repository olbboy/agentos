import Foundation

/// The layout of the root `~/.ageos/` directory. Every path goes through here; tests set
/// `AGEOS_HOME` so they never touch the real home — which is why `~` is NEVER hardcoded elsewhere.
public struct AgeOSHome: Sendable {
    public let root: URL

    /// Precedence: an explicit argument > the `AGEOS_HOME` env var > `~/.ageos`.
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

    /// Creates the whole directory tree (idempotent).
    public func ensureLayout() throws {
        for dir in [root, libraryDir, skillsLibraryDir, mcpLibraryDir, backupsDir, adaptersDir, cacheDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Expands a `~/...` or absolute path into a URL (used for adapter specs).
    public static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}
