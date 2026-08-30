import Foundation

/// Extracts a tarball with the system `/usr/bin/tar` (present on every macOS).
/// Writing a pure-Swift untar is complexity the MVP does not need.
public enum TarballExtractor {
    /// Extracts a `.tar.gz` into `destination` and returns the single top-level directory
    /// (a GitHub tarball always wraps everything in `owner-repo-sha/`).
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
            throw AgeOSError(.processFailed, "tar extraction failed (exit \(process.terminationStatus)): \(err.prefix(200))",
                             remedy: "The downloaded file may be corrupt — run `ageos sync` again")
        }
        let entries = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.hasDirectoryPath }
        guard let top = entries.first, entries.count == 1 else {
            return destination // the tarball has no wrapping top directory → use destination itself
        }
        return top
    }
}
