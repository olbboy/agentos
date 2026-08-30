import Foundation
import CryptoKit

/// A local source: one directory on disk holding one or more skills.
/// The version is a content hash (deterministic) — change a file and you get a new version.
public struct LocalSource: SourceProvider {
    public let descriptor: SourceDescriptor

    public init(descriptor: SourceDescriptor) {
        self.descriptor = descriptor
    }

    public static func makeDescriptor(path: String) throws -> SourceDescriptor {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw AgeOSError(.invalidSource, "Directory does not exist: \(url.path)",
                             remedy: "Check the path, or use a GitHub URL for a remote source")
        }
        let slug = url.lastPathComponent.lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
        return SourceDescriptor(id: "local/\(slug)", kind: .local, location: url.path)
    }

    public func fetch(staging: URL) async throws -> SourceFetchResult {
        let root = URL(fileURLWithPath: descriptor.location, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw AgeOSError(.invalidSource, "Local source disappeared: \(root.path)",
                             remedy: "Restore the directory, or run `ageos source remove \(descriptor.id)`")
        }
        let scan = SkillScanner.scan(root: root)
        let version = contentHash(of: scan.skills)
        var updated = descriptor
        let changed = version != descriptor.lastVersion
        updated.lastVersion = version
        updated.lastSync = Date()
        return SourceFetchResult(version: version, changed: changed, skills: scan.skills.map(FetchedSkill.init),
                                 skipped: scan.skipped, descriptor: updated)
    }

    /// A stable hash over the name plus every file in each skill directory, sorted by path.
    func contentHash(of skills: [ParsedSkill]) -> String {
        var hasher = SHA256()
        let fm = FileManager.default
        for skill in skills.sorted(by: { $0.manifest.name < $1.manifest.name }) {
            hasher.update(data: Data(skill.manifest.name.utf8))
            let files = (fm.enumerator(at: skill.directory, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL } ?? [])
                .filter { !($0.hasDirectoryPath) }
                .sorted { $0.path < $1.path }
            for f in files {
                hasher.update(data: Data(f.lastPathComponent.utf8))
                if let d = fm.contents(atPath: f.path) { hasher.update(data: d) }
            }
        }
        return String(hasher.finalize().map { String(format: "%02x", $0) }.joined().prefix(12))
    }
}
