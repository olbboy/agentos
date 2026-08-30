import Foundation
import Testing
@testable import AgeOSCore

/// An end-to-end loopback: spawn the real `ageos-mcp` binary and speak JSON-RPC over stdio
/// exactly as an MCP client (Claude Code) would.
@Suite("ageos-mcp loopback", .serialized)
struct McpServerLoopbackTests {
    static var serverBinary: URL {
        // The products dir is the directory holding the test bundle.
        Bundle.module.bundleURL.deletingLastPathComponent().appendingPathComponent("ageos-mcp")
    }

    final class McpClient {
        let process = Process()
        let stdin = Pipe()
        let collector = LineCollector()
        var nextId = 1

        init(homeRoot: URL) throws {
            process.executableURL = McpServerLoopbackTests.serverBinary
            var env = ProcessInfo.processInfo.environment
            env["AGEOS_HOME"] = homeRoot.path
            process.environment = env
            process.standardInput = stdin
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            let collector = self.collector
            stdout.fileHandleForReading.readabilityHandler = { handle in
                collector.feed(handle.availableData)
            }
            try process.run()
        }

        func request(_ method: String, params: String = "{}") throws -> [String: Any] {
            let id = nextId
            nextId += 1
            let msg = #"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)","params":\#(params)}"#
            stdin.fileHandleForWriting.write(Data((msg + "\n").utf8))
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                guard let line = collector.nextLine(waitUntil: deadline) else { break }
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      obj["id"] as? Int == id else { continue }
                return obj
            }
            throw AgeOSError(.network, "ageos-mcp did not answer \(method)")
        }

        func notify(_ method: String) {
            stdin.fileHandleForWriting.write(Data((#"{"jsonrpc":"2.0","method":"\#(method)"}"# + "\n").utf8))
        }

        func callTool(_ name: String, args: String) throws -> (text: String, isError: Bool) {
            let resp = try request("tools/call", params: #"{"name":"\#(name)","arguments":\#(args)}"#)
            guard let result = resp["result"] as? [String: Any],
                  let content = result["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String else {
                throw AgeOSError(.network, "Unexpected tools/call payload: \(resp)")
            }
            return (text, (result["isError"] as? Bool) ?? false)
        }

        func shutdown() {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    @Test func fullSelfServeFlow() async throws {
        try await withTempHome { home in
            // A fake agent to enable into (the adapter exists only in the fake home — the real machine is untouched).
            let world = try FakeAgentWorld.setUp(home: home)
            // A local source holding one skill to "install".
            let src = home.root.appendingPathComponent("skill-src")
            try makeSkillDir(in: src, name: "self-serve", description: "skill installed by an agent through ageos-mcp end to end")

            let client = try McpClient(homeRoot: home.root)
            defer { client.shutdown() }

            // 1. The standard MCP handshake.
            let initResp = try client.request("initialize",
                params: #"{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"loopback","version":"0"}}"#)
            let serverInfo = ((initResp["result"] as? [String: Any])?["serverInfo"] as? [String: Any])
            #expect(serverInfo?["name"] as? String == "ageos")
            client.notify("notifications/initialized")

            // 2. All 9 tools present, with short descriptions (this server faces the Budget Meter too).
            let toolsResp = try client.request("tools/list")
            let tools = ((toolsResp["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
            #expect(tools.count == 9)
            let names = Set(tools.compactMap { $0["name"] as? String })
            #expect(names.isSuperset(of: ["search_skills", "skill_info", "install_skill", "enable_skill",
                                          "disable_skill", "list_targets", "scan_library", "budget_report", "doctor"]))
            for t in tools {
                let desc = (t["description"] as? String) ?? ""
                #expect(desc.count < 120, "tool description '\(t["name"] ?? "?")' is \(desc.count) chars — a bad example on budget")
            }

            // 3. install_skill (a local source) → search finds it → enable into the fake agent.
            let install = try client.callTool("install_skill", args: #"{"source":"\#(src.path)"}"#)
            #expect(!install.isError, "\(install.text)")
            #expect(install.text.contains("self-serve"))

            let search = try client.callTool("search_skills", args: #"{"query":"self-serve"}"#)
            #expect(search.text.contains("local/skill-src/self-serve"))

            let enable = try client.callTool("enable_skill",
                                             args: #"{"skill":"self-serve","target":"sym-agent"}"#)
            #expect(!enable.isError, "\(enable.text)")
            #expect(FileManager.default.fileExists(
                atPath: world.symSkillPath("self-serve").appendingPathComponent("SKILL.md").path))

            // 4. doctor and budget run through MCP.
            let doctor = try client.callTool("doctor", args: "{}")
            #expect(!doctor.isError)
            let budget = try client.callTool("budget_report", args: #"{"target":"sym-agent"}"#)
            #expect(budget.text.contains("skillTokens"))

            // 5. disable cleans up.
            let disable = try client.callTool("disable_skill",
                                              args: #"{"skill":"self-serve","target":"sym-agent"}"#)
            #expect(!disable.isError, "\(disable.text)")
            #expect(!FileManager.default.fileExists(atPath: world.symSkillPath("self-serve").path))

            // 6. A wrong tool name → isError, not a crash.
            let bad = try client.callTool("skill_info", args: #"{"skill":"does-not-exist-xyz"}"#)
            #expect(bad.isError)
        }
    }
}
