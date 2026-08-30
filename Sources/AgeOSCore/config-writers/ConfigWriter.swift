import Foundation

/// Hợp đồng ghi config client. Bất biến an toàn (mọi writer PHẢI giữ):
/// 1. KHÔNG BAO GIỜ regenerate cả file — chỉ parse-merge entry của mình.
/// 2. Key lạ/entry user giữ nguyên vẹn.
/// 3. File hỏng sẵn → TỪ CHỐI ghi + chỉ chỗ lỗi (không phá thêm).
/// 4. Ghi atomic; backup do McpManager làm TRƯỚC khi gọi writer.
public protocol ConfigWriter: Sendable {
    /// Thêm/cập nhật entry `name` dưới keyPath. Tạo file mới nếu chưa tồn tại.
    func upsertEntry(name: String, launch: McpServerModel.Launch, keyPath: String, in file: URL) throws
    /// Gỡ entry `name`. Không lỗi nếu entry không tồn tại (idempotent).
    func removeEntry(name: String, keyPath: String, in file: URL) throws
    /// Entry `name` có tồn tại không (file không tồn tại → false).
    func hasEntry(name: String, keyPath: String, in file: URL) throws -> Bool
}

/// Backup config vào `~/.ageos/backups/<timestamp>/` trước MỌI lần ghi.
public enum ConfigBackup {
    static let stampFormat: Date.ISO8601FormatStyle = .iso8601

    /// Trả URL bản backup (nil nếu file gốc chưa tồn tại — không có gì để backup).
    /// Backup KHÔNG BAO GIỜ đè backup cũ: stamp tới mili-giây + suffix khi vẫn trùng
    /// (hai thao tác trong cùng giây từng làm restore lấy nhầm bản).
    @discardableResult
    public static func backup(_ file: URL, home: AgeOSHome) throws -> URL? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
            .replacingOccurrences(of: ":", with: "-")
        let dir = home.backupsDir.appendingPathComponent(stamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Encode path đầy đủ vào tên file để restore biết đường về.
        let encoded = file.path.replacingOccurrences(of: "/", with: "%2F")
        var dest = dir.appendingPathComponent(encoded)
        var suffix = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            suffix += 1
            dest = dir.appendingPathComponent("\(encoded).\(suffix)")
        }
        try FileManager.default.copyItem(at: file, to: dest)
        return dest
    }

    public struct BackupRecord: Sendable, Codable {
        public var timestamp: String
        public var originalPath: String
        public var backupPath: String
    }

    public static func list(home: AgeOSHome) -> [BackupRecord] {
        let fm = FileManager.default
        guard let stamps = try? fm.contentsOfDirectory(atPath: home.backupsDir.path) else { return [] }
        var records: [BackupRecord] = []
        for stamp in stamps.sorted() {
            let dir = home.backupsDir.appendingPathComponent(stamp, isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for f in files.sorted() {
                // Bỏ suffix chống trùng `.N` (nếu có) trước khi decode path gốc.
                let base = f.replacingOccurrences(of: #"\.\d+$"#, with: "", options: .regularExpression)
                let original = base.replacingOccurrences(of: "%2F", with: "/")
                records.append(.init(timestamp: stamp, originalPath: original,
                                     backupPath: dir.appendingPathComponent(f).path))
            }
        }
        return records
    }

    /// Restore bản backup MỚI NHẤT của một file (hoặc của mọi file nếu `original == nil` thì lỗi — phải chỉ định).
    public static func restoreLatest(of original: URL, home: AgeOSHome) throws -> BackupRecord {
        let matches = list(home: home).filter { $0.originalPath == original.path }
        guard let latest = matches.last else {
            throw AgeOSError(.notFound, "Không có backup nào cho \(original.path)",
                             remedy: "Xem danh sách: `ageos mcp restore-backup --list`")
        }
        // Backup chính file hiện tại trước khi đè (revert cũng revert được).
        _ = try? backup(original, home: home)
        let data = try Data(contentsOf: URL(fileURLWithPath: latest.backupPath))
        try AtomicFile.write(data, to: original)
        return latest
    }
}
