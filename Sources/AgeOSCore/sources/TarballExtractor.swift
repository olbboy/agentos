import Foundation

/// Giải nén tarball qua `/usr/bin/tar` hệ thống (có sẵn trên mọi macOS).
/// Viết untar thuần Swift là phức tạp không cần thiết cho MVP.
public enum TarballExtractor {
    /// Giải nén `.tar.gz` vào `destination`, trả về thư mục top-level duy nhất
    /// (tarball GitHub luôn bọc mọi thứ trong `owner-repo-sha/`).
    public static func extract(_ tarball: URL, into destination: URL) throws -> URL {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", tarball.path, "-C", destination.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AgeOSError(.processFailed, "tar giải nén thất bại (exit \(process.terminationStatus)): \(err.prefix(200))",
                             remedy: "File tải về có thể hỏng — chạy lại `ageos sync`")
        }
        let entries = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.hasDirectoryPath }
        guard let top = entries.first, entries.count == 1 else {
            return destination // tarball không bọc top-dir → dùng chính destination
        }
        return top
    }
}
