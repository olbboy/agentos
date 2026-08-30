import Foundation
import CryptoKit

/// Nguồn local: một thư mục trên đĩa chứa 1..n skill.
/// Version = hash nội dung (deterministic) — đổi file là ra version mới.
public struct LocalSource: SourceProvider {
    public let descriptor: SourceDescriptor

    public init(descriptor: SourceDescriptor) {
        self.descriptor = descriptor
    }

    public static func makeDescriptor(path: String) throws -> SourceDescriptor {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw AgeOSError(.invalidSource, "Thư mục không tồn tại: \(url.path)",
                             remedy: "Kiểm tra path hoặc dùng URL GitHub cho nguồn remote")
        }
        let slug = url.lastPathComponent.lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
        return SourceDescriptor(id: "local/\(slug)", kind: .local, location: url.path)
    }

    public func fetch(staging: URL) async throws -> SourceFetchResult {
        let root = URL(fileURLWithPath: descriptor.location, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw AgeOSError(.invalidSource, "Nguồn local biến mất: \(root.path)",
                             remedy: "Khôi phục thư mục hoặc `ageos source remove \(descriptor.id)`")
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

    /// Hash ổn định trên (tên + toàn bộ file trong từng skill dir, sort theo path).
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
