import Foundation
import Testing
@testable import AgeOSCore

@Suite("ConfigWriter JSON golden")
struct JsonConfigWriterTests {
    let writer = JsonConfigWriter()
    let launch = McpServerModel.Launch(transport: .stdio, command: "npx",
                                       args: ["-y", "test-server"], env: ["FOO": "bar"])

    func tempFile(_ content: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfg-\(UUID().uuidString.prefix(8)).json")
        if let content {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    @Test func preservesUnknownKeysAndUserEntries() throws {
        let file = try tempFile("""
        {
          "theme": "dark",
          "numStartups": 42,
          "mcpServers": {
            "user-server": {"command": "deno", "args": ["run", "x.ts"], "customKey": true}
          },
          "nested": {"deep": [1, 2, 3]}
        }
        """)
        defer { try? FileManager.default.removeItem(at: file) }

        try writer.upsertEntry(name: "ageos-added", launch: launch, keyPath: "mcpServers", in: file)

        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        #expect(root["theme"] as? String == "dark")
        #expect(root["numStartups"] as? Int == 42)
        #expect((root["nested"] as? [String: Any])?["deep"] as? [Int] == [1, 2, 3])
        let servers = root["mcpServers"] as! [String: Any]
        let userEntry = servers["user-server"] as! [String: Any]
        #expect(userEntry["command"] as? String == "deno")
        #expect(userEntry["customKey"] as? Bool == true)
        let ours = servers["ageos-added"] as! [String: Any]
        #expect(ours["command"] as? String == "npx")
        #expect((ours["env"] as? [String: String])?["FOO"] == "bar")

        // Remove takes out only our entry; the user's entry and unknown keys survive.
        try writer.removeEntry(name: "ageos-added", keyPath: "mcpServers", in: file)
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let serversAfter = after["mcpServers"] as! [String: Any]
        #expect(serversAfter["ageos-added"] == nil)
        #expect(serversAfter["user-server"] != nil)
        #expect(after["theme"] as? String == "dark")
    }

    @Test func refusesBrokenJson() throws {
        let file = try tempFile(#"{"mcpServers": {broken"#)
        defer { try? FileManager.default.removeItem(at: file) }
        let before = try Data(contentsOf: file)
        #expect(throws: AgeOSError.self) {
            try writer.upsertEntry(name: "x", launch: launch, keyPath: "mcpServers", in: file)
        }
        // The malformed file is left untouched.
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func createsFileWhenMissing() throws {
        let file = try tempFile(nil)
        defer { try? FileManager.default.removeItem(at: file) }
        try writer.upsertEntry(name: "fresh", launch: launch, keyPath: "mcpServers", in: file)
        #expect(try writer.hasEntry(name: "fresh", keyPath: "mcpServers", in: file))
    }

    @Test func httpEntryFormat() throws {
        let file = try tempFile(nil)
        defer { try? FileManager.default.removeItem(at: file) }
        let http = McpServerModel.Launch(transport: .http, url: "https://mcp.example.com/mcp")
        try writer.upsertEntry(name: "remote", launch: http, keyPath: "mcpServers", in: file)
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let entry = (root["mcpServers"] as! [String: Any])["remote"] as! [String: Any]
        #expect(entry["type"] as? String == "http")
        #expect(entry["url"] as? String == "https://mcp.example.com/mcp")
    }
}

@Suite("ConfigWriter TOML golden")
struct TomlConfigWriterTests {
    let launch = McpServerModel.Launch(transport: .stdio, command: "npx",
                                       args: ["-y", "test-server"], env: ["KEY": "val"])

    func tempFile(_ content: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfg-\(UUID().uuidString.prefix(8)).toml")
        if let content {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    @Test func preservesExistingSectionsAndValues() throws {
        let file = try tempFile("""
        model = "gpt-5.6-sol"

        [profiles.work]
        approval = "never"

        [mcp_servers.user-server]
        command = "deno"
        args = ["run", "srv.ts"]
        """)
        defer { try? FileManager.default.removeItem(at: file) }

        var writer = TomlConfigWriter()
        writer.onWarning = { _ in }
        try writer.upsertEntry(name: "ageos-added", launch: launch, keyPath: "mcp_servers", in: file)

        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("model") && text.contains("gpt-5.6-sol")) // TOMLKit may change the quote style
        #expect(text.contains("[profiles.work]") || text.contains("profiles.work") || text.contains("[profiles]"))
        #expect(text.contains("user-server"))
        #expect(text.contains("ageos-added"))
        #expect(text.contains("npx"))

        try writer.removeEntry(name: "ageos-added", keyPath: "mcp_servers", in: file)
        let after = try String(contentsOf: file, encoding: .utf8)
        #expect(!after.contains("ageos-added"))
        #expect(after.contains("user-server"))
        #expect(after.contains("model") && after.contains("gpt-5.6-sol"))
    }

    @Test func warnsWhenFileHasComments() throws {
        let file = try tempFile("""
        # a comment the user cares about
        [mcp_servers.existing]
        command = "x"
        """)
        defer { try? FileManager.default.removeItem(at: file) }
        let warned = LockedFlag()
        var writer = TomlConfigWriter()
        writer.onWarning = { _ in warned.set() }
        try writer.upsertEntry(name: "n", launch: launch, keyPath: "mcp_servers", in: file)
        #expect(warned.isSet())
    }

    @Test func refusesBrokenToml() throws {
        let file = try tempFile("[mcp_servers.x\ncommand=")
        defer { try? FileManager.default.removeItem(at: file) }
        var writer = TomlConfigWriter()
        writer.onWarning = { _ in }
        #expect(throws: AgeOSError.self) {
            try writer.upsertEntry(name: "x", launch: launch, keyPath: "mcp_servers", in: file)
        }
    }
}

/// Flag thread-safe cho callback test.
final class LockedFlag: @unchecked Sendable {
    private var value = false
    private let lock = NSLock()
    func set() { lock.lock(); value = true; lock.unlock() }
    func isSet() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}
