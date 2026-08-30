import Foundation
import Testing
@testable import AgeOSCore

/// Fake world MCP: 3 client giả (2 JSON + 1 TOML) với config path trong temp home.
struct FakeMcpWorld {
    let home: AgeOSHome
    let clientsRoot: URL

    static func setUp(home: AgeOSHome) throws -> FakeMcpWorld {
        let clientsRoot = home.root.appendingPathComponent("fake-clients", isDirectory: true)
        try FileManager.default.createDirectory(at: clientsRoot, withIntermediateDirectories: true)

        func adapter(id: String, format: String, configName: String, keyPath: String, projectConfig: String?) -> String {
            let project = projectConfig.map { "\"projectConfigPath\": \"\($0)\"," } ?? ""
            return """
            {
              "schemaVersion": 1, "id": "\(id)", "displayName": "\(id)",
              "detect": ["\(clientsRoot.path)"],
              "skills": null,
              "mcp": {"configPath": "\(clientsRoot.path)/\(configName)", \(project)
                      "format": "\(format)", "keyPath": "\(keyPath)", "verified": true},
              "budget": null, "notes": null
            }
            """
        }
        try adapter(id: "json-a", format: "json", configName: "json-a.json", keyPath: "mcpServers", projectConfig: ".mcp.json")
            .write(to: home.adaptersDir.appendingPathComponent("json-a.json"), atomically: true, encoding: .utf8)
        try adapter(id: "json-b", format: "json", configName: "json-b.json", keyPath: "mcpServers", projectConfig: nil)
            .write(to: home.adaptersDir.appendingPathComponent("json-b.json"), atomically: true, encoding: .utf8)
        try adapter(id: "toml-c", format: "toml", configName: "toml-c.toml", keyPath: "mcp_servers", projectConfig: nil)
            .write(to: home.adaptersDir.appendingPathComponent("toml-c.json"), atomically: true, encoding: .utf8)
        return FakeMcpWorld(home: home, clientsRoot: clientsRoot)
    }

    func manager() throws -> McpManager {
        McpManager(home: home, adapters: try AdapterRegistry(home: home, includeBundled: false),
                   warningSink: nil)
    }

    func config(_ name: String) -> URL {
        clientsRoot.appendingPathComponent(name)
    }
}

let testModel = McpServerModel(
    id: "io.github.test/echo", name: "echo", description: "test server",
    version: "1.0.0", source: "test",
    launch: .init(transport: .stdio, command: "npx", args: ["-y", "echo-mcp"]),
    envSchema: [.init(name: "API_KEY", description: "khóa", required: true, secret: true)]
)

@Suite("McpManager enable/disable 3 client")
struct McpManagerTests {
    /// Success criterion #1 Phase 4: enable cùng server cho 3 client, format đúng từng client,
    /// key lạ còn nguyên, có backup.
    @Test func enableToThreeClientsWithCorrectFormats() async throws {
        try await withTempHome { home in
            let world = try FakeMcpWorld.setUp(home: home)
            // json-a có sẵn config với key lạ + entry user.
            try """
            {"existingSetting": true, "mcpServers": {"user-owned": {"command": "bun"}}}
            """.write(to: world.config("json-a.json"), atomically: true, encoding: .utf8)
            try """
            model = "grok-4"
            [mcp_servers.user-toml]
            command = "deno"
            """.write(to: world.config("toml-c.toml"), atomically: true, encoding: .utf8)

            let manager = try world.manager()
            try manager.library.upsert(testModel)

            let o1 = try manager.enable(query: "echo", adapterId: "json-a", envOverrides: ["API_KEY": "sk-test"])
            let o2 = try manager.enable(query: "echo", adapterId: "json-b", envOverrides: ["API_KEY": "sk-test"])
            let o3 = try manager.enable(query: "echo", adapterId: "toml-c", envOverrides: ["API_KEY": "sk-test"])
            #expect(o1.backupPath != nil)   // json-a có file sẵn → phải có backup
            #expect(o2.backupPath == nil)   // json-b chưa có file → không có gì để backup
            #expect(o3.sensitiveEnv == ["API_KEY"])
            #expect(o1.note?.contains("PLAINTEXT") == true)

            // json-a: key lạ + entry user nguyên vẹn, entry mình đúng format.
            let rootA = try JSONSerialization.jsonObject(with: Data(contentsOf: world.config("json-a.json"))) as! [String: Any]
            #expect(rootA["existingSetting"] as? Bool == true)
            let serversA = rootA["mcpServers"] as! [String: Any]
            #expect((serversA["user-owned"] as? [String: Any])?["command"] as? String == "bun")
            let mine = serversA["echo"] as! [String: Any]
            #expect(mine["command"] as? String == "npx")
            #expect((mine["env"] as? [String: String])?["API_KEY"] == "sk-test")

            // toml-c: giữ model + user entry, thêm mình.
            let tomlText = try String(contentsOf: world.config("toml-c.toml"), encoding: .utf8)
            #expect(tomlText.contains("model") && tomlText.contains("grok-4")) // TOMLKit có thể đổi kiểu quote
            #expect(tomlText.contains("user-toml"))
            #expect(tomlText.contains("echo"))

            // Lockfile ghi nhận 3 target + sensitiveEnv.
            let lock = try Lockfile.load(from: home.lockfilePath)
            let entry = lock.mcpServers["io.github.test/echo"]
            #expect(entry?.targets.count == 3)
            #expect(entry?.sensitiveEnv == ["API_KEY"])

            // Disable json-a: chỉ gỡ entry mình.
            _ = try manager.disable(query: "echo", adapterId: "json-a")
            let afterA = try JSONSerialization.jsonObject(with: Data(contentsOf: world.config("json-a.json"))) as! [String: Any]
            let serversAfter = afterA["mcpServers"] as! [String: Any]
            #expect(serversAfter["echo"] == nil)
            #expect(serversAfter["user-owned"] != nil)
        }
    }

    @Test func missingRequiredEnvBlocksEnable() async throws {
        try await withTempHome { home in
            let world = try FakeMcpWorld.setUp(home: home)
            let manager = try world.manager()
            try manager.library.upsert(testModel)
            do {
                _ = try manager.enable(query: "echo", adapterId: "json-b")
                Issue.record("Phải chặn khi thiếu env bắt buộc")
            } catch let e as AgeOSError {
                #expect(e.message.contains("API_KEY"))
                #expect(e.remedy?.contains("--env") == true)
            }
        }
    }

    @Test func userEntryCollisionBlocksEnable() async throws {
        try await withTempHome { home in
            let world = try FakeMcpWorld.setUp(home: home)
            try #"{"mcpServers": {"echo": {"command": "user-thing"}}}"#
                .write(to: world.config("json-b.json"), atomically: true, encoding: .utf8)
            let manager = try world.manager()
            try manager.library.upsert(testModel)
            do {
                _ = try manager.enable(query: "echo", adapterId: "json-b", envOverrides: ["API_KEY": "x"])
                Issue.record("Phải chặn khi entry trùng tên của user")
            } catch let e as AgeOSError {
                #expect(e.code == .conflict)
            }
            // Entry user nguyên vẹn.
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: world.config("json-b.json"))) as! [String: Any]
            #expect(((root["mcpServers"] as! [String: Any])["echo"] as! [String: Any])["command"] as? String == "user-thing")
        }
    }

    @Test func projectScopeWritesProjectConfig() async throws {
        try await withTempHome { home in
            let world = try FakeMcpWorld.setUp(home: home)
            let manager = try world.manager()
            try manager.library.upsert(testModel)
            let project = home.root.appendingPathComponent("proj", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let outcome = try manager.enable(query: "echo", adapterId: "json-a",
                                             project: project, envOverrides: ["API_KEY": "x"])
            #expect(outcome.scope == "project")
            #expect(outcome.configPath == project.appendingPathComponent(".mcp.json").path)
            #expect(FileManager.default.fileExists(atPath: outcome.configPath))
        }
    }

    @Test func backupAndRestoreRoundtrip() async throws {
        try await withTempHome { home in
            let world = try FakeMcpWorld.setUp(home: home)
            let original = #"{"mcpServers": {}, "precious": "data"}"#
            try original.write(to: world.config("json-b.json"), atomically: true, encoding: .utf8)
            let manager = try world.manager()
            try manager.library.upsert(testModel)
            _ = try manager.enable(query: "echo", adapterId: "json-b", envOverrides: ["API_KEY": "x"])

            // Config đã đổi; restore đưa về nguyên bản.
            let restored = try ConfigBackup.restoreLatest(of: world.config("json-b.json"), home: home)
            #expect(restored.originalPath == world.config("json-b.json").path)
            let text = try String(contentsOf: world.config("json-b.json"), encoding: .utf8)
            #expect(text.contains("precious"))
            #expect(!text.contains("echo"))
        }
    }
}
