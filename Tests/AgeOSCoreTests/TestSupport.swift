import Foundation
@testable import AgeOSCore

/// Fixtures bundle dir.
func fixturesDir() -> URL {
    Bundle.module.resourceURL!.appendingPathComponent("Fixtures", isDirectory: true)
}

/// Runs the body with a temporary AGEOS_HOME — no test may ever touch the real home.
func withTempHome<T>(_ body: (AgeOSHome) async throws -> T) async throws -> T {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ageos-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
    let home = AgeOSHome(root: root)
    try home.ensureLayout()
    defer { try? FileManager.default.removeItem(at: root) }
    return try await body(home)
}

func withTempHomeSync<T>(_ body: (AgeOSHome) throws -> T) throws -> T {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ageos-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
    let home = AgeOSHome(root: root)
    try home.ensureLayout()
    defer { try? FileManager.default.removeItem(at: root) }
    return try body(home)
}

/// Mock HTTP: map URL string → (status, data, headers).
struct MockHTTPClient: HTTPClient {
    struct Stub: Sendable {
        var status: Int
        var data: Data
        var headers: [String: String] = [:]
    }

    var stubs: [String: Stub]

    func get(_ url: URL, headers: [String: String]) async throws -> (data: Data, response: HTTPURLResponse) {
        guard let stub = stubs[url.absoluteString] else {
            throw AgeOSError(.network, "MockHTTPClient: no stub for \(url.absoluteString)")
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                       headerFields: stub.headers)!
        return (stub.data, response)
    }
}

/// Creates a temporary skill directory with the given SKILL.md content.
@discardableResult
func makeSkillDir(in parent: URL, name: String, description: String, body: String = "# Test\n") throws -> URL {
    let dir = parent.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let content = """
    ---
    name: \(name)
    description: \(description)
    ---
    \(body)
    """
    try content.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    return dir
}

/// Packs a directory into a tar.gz (mimicking a GitHub tarball with its top directory).
func makeTarball(of dir: URL, topDirName: String) throws -> URL {
    let staging = FileManager.default.temporaryDirectory
        .appendingPathComponent("tarball-\(UUID().uuidString.prefix(8))", isDirectory: true)
    let top = staging.appendingPathComponent(topDirName, isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: dir, to: top)
    let out = staging.appendingPathComponent("repo.tar.gz")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    p.arguments = ["-czf", out.path, "-C", staging.path, topDirName]
    try p.run()
    p.waitUntilExit()
    precondition(p.terminationStatus == 0, "tar czf failed")
    return out
}
