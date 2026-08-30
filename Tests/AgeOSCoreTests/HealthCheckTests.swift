import Foundation
import Testing
@testable import AgeOSCore

@Suite("HealthCheck stdio")
struct HealthCheckTests {
    /// Server MCP giả bằng python3: trả lời initialize + tools/list đúng protocol.
    func makeFakeServer() throws -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-mcp-\(UUID().uuidString.prefix(8)).py")
        try #"""
        import sys, json
        for line in sys.stdin:
            try:
                req = json.loads(line)
            except Exception:
                continue
            rid = req.get("id")
            method = req.get("method", "")
            if method == "initialize":
                resp = {"jsonrpc": "2.0", "id": rid, "result": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "fake-mcp", "version": "9.9.9"}}}
            elif method == "tools/list":
                resp = {"jsonrpc": "2.0", "id": rid, "result": {"tools": [
                    {"name": "ping", "description": "pong", "inputSchema": {"type": "object"}},
                    {"name": "echo", "description": "echo text", "inputSchema": {"type": "object"}}]}}
            elif rid is None:
                continue
            else:
                resp = {"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "nope"}}
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()
        """#.write(to: script, atomically: true, encoding: .utf8)
        return script
    }

    @Test func healthyServerReportsToolsAndLatency() throws {
        let script = try makeFakeServer()
        defer { try? FileManager.default.removeItem(at: script) }
        let launch = McpServerModel.Launch(transport: .stdio, command: "python3", args: [script.path])
        let report = HealthCheck.run(launch, timeout: 20)
        #expect(report.ok, "health fail: \(report.error ?? "?") stderr: \(report.stderrTail ?? "")")
        #expect(report.toolCount == 2)
        #expect(report.schemaTokens > 10)
        #expect(report.serverInfo?.contains("fake-mcp") == true)
        #expect(report.latencyMs < 20_000)
    }

    @Test func badCommandFailsCleanly() {
        let launch = McpServerModel.Launch(transport: .stdio,
                                           command: "/nonexistent/definitely-not-a-command-xyz", args: [])
        let report = HealthCheck.run(launch, timeout: 5)
        #expect(!report.ok)
        #expect(report.error != nil)
    }

    @Test func hangingServerHitsTimeoutAndGetsKilled() throws {
        // Server "treo": đọc stdin nhưng không bao giờ trả lời.
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("hang-\(UUID().uuidString.prefix(8)).py")
        try "import time\nwhile True: time.sleep(1)\n".write(to: script, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: script) }
        let launch = McpServerModel.Launch(transport: .stdio, command: "python3", args: [script.path])
        let started = Date()
        let report = HealthCheck.run(launch, timeout: 3)
        #expect(!report.ok)
        #expect(Date().timeIntervalSince(started) < 10) // timeout + kill grace, không treo mãi
        // Không process mồ côi: python script này phải chết sau run().
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        check.arguments = ["-f", script.lastPathComponent]
        let out = Pipe()
        check.standardOutput = out
        try check.run()
        check.waitUntilExit()
        let survivors = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(survivors.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "process mồ côi còn sống: \(survivors)")
    }

    @Test func httpTransportIsSkippedInMvp() {
        let launch = McpServerModel.Launch(transport: .http, url: "https://example.com/mcp")
        let report = HealthCheck.run(launch)
        #expect(!report.ok)
        #expect(report.error?.contains("stdio") == true)
    }
}

@Suite("McpbImporter")
struct McpbImporterTests {
    @Test func importsBundleAndResolvesDirname() async throws {
        try await withTempHome { home in
            // Dựng bundle .mcpb: manifest + payload, nén bằng ditto.
            let stage = home.root.appendingPathComponent("bundle-src", isDirectory: true)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            try #"""
            {"name": "My Fancy Server", "version": "2.1.0", "description": "test bundle",
             "server": {"type": "node", "entry_point": "server/index.js",
                        "mcp_config": {"command": "node", "args": ["${__dirname}/server/index.js"],
                                       "env": {"DATA_DIR": "${__dirname}/data"}}}}
            """#.write(to: stage.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: stage.appendingPathComponent("server"), withIntermediateDirectories: true)
            try "// fake".write(to: stage.appendingPathComponent("server/index.js"), atomically: true, encoding: .utf8)

            let bundle = home.root.appendingPathComponent("fancy.mcpb")
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            zip.arguments = ["-c", "-k", stage.path, bundle.path]
            try zip.run()
            zip.waitUntilExit()
            #expect(zip.terminationStatus == 0)

            let model = try McpbImporter.importBundle(at: bundle, home: home)
            #expect(model.id == "local/my-fancy-server")
            #expect(model.version == "2.1.0")
            #expect(model.launch.command == "node")
            // ${__dirname} resolve vào library, và file thật sự nằm đó.
            let arg = model.launch.args[0]
            #expect(arg.contains("/library/mcp/local/my-fancy-server/2.1.0"))
            #expect(FileManager.default.fileExists(atPath: arg))
            #expect(model.launch.env["DATA_DIR"]?.contains("/library/mcp/") == true)
        }
    }

    @Test func missingManifestFails() async throws {
        try await withTempHome { home in
            let stage = home.root.appendingPathComponent("empty-src", isDirectory: true)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            try "x".write(to: stage.appendingPathComponent("whatever.txt"), atomically: true, encoding: .utf8)
            let bundle = home.root.appendingPathComponent("bad.mcpb")
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            zip.arguments = ["-c", "-k", stage.path, bundle.path]
            try zip.run()
            zip.waitUntilExit()
            #expect(throws: AgeOSError.self) {
                _ = try McpbImporter.importBundle(at: bundle, home: home)
            }
        }
    }
}

@Suite("McpRegistrySource decode")
struct McpRegistryDecodeTests {
    @Test func decodesWrappedAndFlatShapes() throws {
        let wrapped = #"""
        {"servers": [{"server": {"name": "io.github.acme/tool", "description": "d", "version": "1.0.0",
            "packages": [{"registry_type": "npm", "identifier": "acme-tool", "version": "1.0.0",
                          "environment_variables": [{"name": "TOKEN", "is_required": true, "is_secret": true}]}]}}]}
        """#
        let flat = #"""
        {"servers": [{"name": "io.github.flat/one", "description": "d2",
                      "remotes": [{"type": "streamable-http", "url": "https://x.dev/mcp"}]}]}
        """#
        let a = try McpRegistrySource.decodeList(Data(wrapped.utf8))
        #expect(a.count == 1)
        let modelA = McpRegistrySource.model(from: a[0])
        #expect(modelA?.launch.command == "npx")
        #expect(modelA?.launch.args == ["-y", "acme-tool@1.0.0"])
        #expect(modelA?.envSchema.first?.secret == true)

        let b = try McpRegistrySource.decodeList(Data(flat.utf8))
        let modelB = McpRegistrySource.model(from: b[0])
        #expect(modelB?.launch.transport == .http)
        #expect(modelB?.launch.url == "https://x.dev/mcp")
    }
}
