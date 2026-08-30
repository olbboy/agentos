import Foundation
import Testing
@testable import AgeOSCore

@Suite("AdapterRegistry bundled + override")
struct AdapterRegistryTests {
    @Test func bundledSixAdaptersDecode() async throws {
        try await withTempHome { home in
            let registry = try AdapterRegistry(home: home)
            let ids = Set(registry.adapters.map(\.id))
            for expected in ["claude-code", "codex", "grok", "antigravity", "claude-desktop", "universal-agents"] {
                #expect(ids.contains(expected), "missing bundled adapter: \(expected)")
            }
            // The spike findings have to live in the data: codex does not accept file symlinks, grok accepts both.
            let codex = try registry.adapter(id: "codex")
            #expect(codex.skills?.fileSymlink == false)
            #expect(codex.skills?.folderSymlink == true)
            #expect(codex.effectiveSkillMode == .copy)
            let grok = try registry.adapter(id: "grok")
            #expect(grok.skills?.fileSymlink == true)
            #expect(grok.mcp?.keyPath == "mcp_servers")
            let desktop = try registry.adapter(id: "claude-desktop")
            #expect(desktop.skills == nil)
            #expect(desktop.mcp != nil)
        }
    }

    @Test func userOverrideWinsById() async throws {
        try await withTempHome { home in
            try """
            {"schemaVersion": 1, "id": "codex", "displayName": "Codex OVERRIDDEN",
             "detect": ["/nonexistent"], "skills": null, "mcp": null, "budget": null, "notes": null}
            """.write(to: home.adaptersDir.appendingPathComponent("codex.json"), atomically: true, encoding: .utf8)
            let registry = try AdapterRegistry(home: home)
            #expect(try registry.adapter(id: "codex").displayName == "Codex OVERRIDDEN")
        }
    }

    @Test func corruptUserAdapterFailsLoud() async throws {
        try await withTempHome { home in
            try "{broken json".write(to: home.adaptersDir.appendingPathComponent("bad.json"),
                                     atomically: true, encoding: .utf8)
            #expect(throws: AgeOSError.self) { _ = try AdapterRegistry(home: home) }
        }
    }
}
