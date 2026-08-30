import Foundation
import Testing
@testable import AgeOSCore

/// A fake MCP world: three fake clients (two JSON, one TOML) with config paths inside a temp home.
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
    envSchema: [.init(name: "API_KEY", description: "key", required: true, secret: true)]
)

@Suite("McpManager enable/disable 3 client")
struct McpManagerTests {
    /// The same server enabled for three clients, each in its own format,
    /// with unknown keys preserved and a backup taken.
    @Test func enableToThreeClientsWithCorrectFormats() async throws {
        try await withTempHome { home in
            let world = try FakeMcpWorld.setUp(home: home)
            // json-a already has a config carrying an unknown key plus a user entry.
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
            #expect(o1.backupPath != nil)   // json-a had a file → a backup is required
            #expect(o2.backupPath == nil)   // json-b had no file → nothing to back up
            #expect(o3.sensitiveEnv == ["API_KEY"])
            #expect(o1.note?.contains("PLAINTEXT") == true)

            // json-a: the unknown key and user entry are intact, and our entry is in the right format.
            let rootA = try JSONSerialization.jsonObject(with: Data(contentsOf: world.config("json-a.json"))) as! [String: Any]
            #expect(rootA["existingSetting"] as? Bool == true)
            let serversA = rootA["mcpServers"] as! [String: Any]
            #expect((serversA["user-owned"] as? [String: Any])?["command"] as? String == "bun")
            let mine = serversA["echo"] as! [String: Any]
            #expect(mine["command"] as? String == "npx")
            #expect((mine["env"] as? [String: String])?["API_KEY"] == "sk-test")

            // toml-c: the model and user entry survive, and ours is added.
            let tomlText = try String(contentsOf: world.config("toml-c.toml"), encoding: .utf8)
            #expect(tomlText.contains("model") && tomlText.contains("grok-4")) // TOMLKit may change the quote style
            #expect(tomlText.contains("user-toml"))
            #expect(tomlText.contains("echo"))

            // The lockfile records three targets plus sensitiveEnv.
            let lock = try Lockfile.load(from: home.lockfilePath)
            let entry = lock.mcpServers["io.github.test/echo"]
            #expect(entry?.targets.count == 3)
            #expect(entry?.sensitiveEnv == ["API_KEY"])

            // Disabling json-a removes only our entry.
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
                Issue.record("It must refuse when required env is missing")
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
                Issue.record("It must refuse when the name collides with a user entry")
            } catch let e as AgeOSError {
                #expect(e.code == .conflict)
            }
            // The user's entry is intact.
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

    @Test func removeFromLibraryGuardsEnabledServers() async throws {
        try await withTempHome { home in
            let world = try FakeMcpWorld.setUp(home: home)
            let manager = try world.manager()
            try manager.library.upsert(testModel)
            _ = try manager.enable(query: "echo", adapterId: "json-b", envOverrides: ["API_KEY": "x"])

            // Still enabled → refuse, and leave the entry in place.
            do {
                _ = try manager.removeFromLibrary(query: "echo")
                Issue.record("Remove must refuse while the server is still enabled")
            } catch let e as AgeOSError {
                #expect(e.code == .conflict)
                #expect(e.remedy?.contains("disable") == true)
            }
            #expect(try manager.library.load().count == 1)

            // Once disabled, remove goes through cleanly.
            _ = try manager.disable(query: "echo", adapterId: "json-b")
            let removed = try manager.removeFromLibrary(query: "echo")
            #expect(removed.id == "io.github.test/echo")
            #expect(try manager.library.load().isEmpty)
            #expect(throws: AgeOSError.self) { _ = try manager.library.find("echo") }
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

            // The config was changed; restore puts the original back.
            let restored = try ConfigBackup.restoreLatest(of: world.config("json-b.json"), home: home)
            #expect(restored.originalPath == world.config("json-b.json").path)
            let text = try String(contentsOf: world.config("json-b.json"), encoding: .utf8)
            #expect(text.contains("precious"))
            #expect(!text.contains("echo"))
        }
    }
}
