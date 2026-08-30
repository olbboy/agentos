import Foundation
import Testing
@testable import AgeOSCore

/// Dựng fake home + fake agent + adapter JSON (không đụng máy thật, không đụng bundled).
struct FakeAgentWorld {
    let home: AgeOSHome
    let agentRoot: URL

    /// Tạo 2 adapter giả: sym-agent (symlink) + copy-agent (copy), path trong temp.
    static func setUp(home: AgeOSHome) throws -> FakeAgentWorld {
        let agentRoot = home.root.appendingPathComponent("fake-agents", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: agentRoot.appendingPathComponent("sym-agent/skills"), withIntermediateDirectories: true)
        try fm.createDirectory(at: agentRoot.appendingPathComponent("copy-agent/skills"), withIntermediateDirectories: true)

        func adapterJSON(id: String, mode: String, folderSymlink: Bool) -> String {
            """
            {
              "schemaVersion": 1, "id": "\(id)", "displayName": "\(id)",
              "detect": ["\(agentRoot.path)/\(id)"],
              "skills": {
                "globalPath": "\(agentRoot.path)/\(id)/skills",
                "projectPath": ".agents/skills",
                "folderSymlink": \(folderSymlink), "fileSymlink": false,
                "preferredMode": "\(mode)", "verified": true
              },
              "mcp": null, "budget": null, "notes": null
            }
            """
        }
        try adapterJSON(id: "sym-agent", mode: "symlink", folderSymlink: true)
            .write(to: home.adaptersDir.appendingPathComponent("sym-agent.json"), atomically: true, encoding: .utf8)
        try adapterJSON(id: "copy-agent", mode: "copy", folderSymlink: false)
            .write(to: home.adaptersDir.appendingPathComponent("copy-agent.json"), atomically: true, encoding: .utf8)
        return FakeAgentWorld(home: home, agentRoot: agentRoot)
    }

    func registry() throws -> AdapterRegistry {
        try AdapterRegistry(home: home, includeBundled: false)
    }

    func symSkillPath(_ name: String) -> URL {
        agentRoot.appendingPathComponent("sym-agent/skills/\(name)")
    }

    func copySkillPath(_ name: String) -> URL {
        agentRoot.appendingPathComponent("copy-agent/skills/\(name)")
    }
}

@Suite("LinkEngine enable/disable/propagate")
struct LinkEngineTests {
    /// Success criterion #1 Phase 3: cùng version enable symlink + copy;
    /// update version → CẢ HAI nhận bản mới.
    @Test func symlinkAndCopyShareVersionAndBothUpdate() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "shared", description: "distribution test skill v1")
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)

            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: try world.registry())
            let ref = SkillRef(id: "local/src/shared")!
            let symOut = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "sym-agent")
            let copyOut = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "copy-agent")
            #expect(symOut.mode == "symlink")
            #expect(copyOut.mode == "copy")

            // Symlink là link thật trỏ vào store; copy là dir thật có manifest + marker.
            let fm = FileManager.default
            #expect((try? fm.destinationOfSymbolicLink(atPath: world.symSkillPath("shared").path)) != nil)
            #expect(CopySync.readManifest(at: world.copySkillPath("shared")) != nil)
            #expect(ManagedMarker.isSet(on: world.copySkillPath("shared").path))

            // Đổi nội dung nguồn → sync → cả hai target đọc ra bản mới.
            try "---\nname: shared\ndescription: distribution test skill v2 UPDATED\n---\nbody v2"
                .write(to: src.appendingPathComponent("shared/SKILL.md"), atomically: true, encoding: .utf8)
            let reports = try await engine.sync()
            #expect(reports[0].changed)
            #expect(reports[0].driftWarnings.isEmpty)

            let viaSymlink = try SkillParser.parse(directory: world.symSkillPath("shared"))
            let viaCopy = try SkillParser.parse(directory: world.copySkillPath("shared"))
            #expect(viaSymlink.manifest.description.contains("v2 UPDATED"))
            #expect(viaCopy.manifest.description.contains("v2 UPDATED"))
        }
    }

    /// Success criterion #2: không đụng file user — trùng tên → dừng + báo; disable sạch.
    @Test func neverOverwritesUserFilesAndDisableIsClean() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "mine", description: "skill that collides with user dir")
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: try world.registry())
            let ref = SkillRef(id: "local/src/mine")!

            // User đã tự tạo skill trùng tên (không marker).
            try makeSkillDir(in: world.agentRoot.appendingPathComponent("sym-agent/skills"),
                             name: "mine", description: "user handmade skill, must survive")
            do {
                _ = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "sym-agent")
                Issue.record("Enable phải từ chối khi đích là đồ user")
            } catch let error as AgeOSError {
                #expect(error.code == .conflict)
            }
            // Đồ user còn nguyên.
            let userSkill = try SkillParser.parse(directory: world.symSkillPath("mine"))
            #expect(userSkill.manifest.description.contains("handmade"))

            // Enable vào copy-agent rồi disable → đích biến mất, lockfile sạch, đồ user vẫn nguyên.
            _ = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "copy-agent")
            _ = try linkEngine.disable(ref, adapterId: "copy-agent")
            #expect(!FileManager.default.fileExists(atPath: world.copySkillPath("mine").path))
            let lock = try Lockfile.load(from: home.lockfilePath)
            #expect(lock.skills["local/src/mine"] == nil)
            #expect(FileManager.default.fileExists(atPath: world.symSkillPath("mine").path))
        }
    }

    @Test func copyDriftIsRespectedOnSync() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "drifty", description: "skill user will edit locally v1")
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: try world.registry())
            let ref = SkillRef(id: "local/src/drifty")!
            _ = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "copy-agent")

            // User sửa bản copy.
            try "user edits: keep me!".write(to: world.copySkillPath("drifty").appendingPathComponent("NOTES.md"),
                                            atomically: true, encoding: .utf8)
            // Nguồn ra version mới.
            try "---\nname: drifty\ndescription: upstream v2 must not clobber\n---\nbody"
                .write(to: src.appendingPathComponent("drifty/SKILL.md"), atomically: true, encoding: .utf8)
            let reports = try await engine.sync()
            #expect(reports[0].driftWarnings.count == 1)
            // File user thêm còn nguyên, description CHƯA bị đè.
            let onDisk = try SkillParser.parse(directory: world.copySkillPath("drifty"))
            #expect(!onDisk.manifest.description.contains("v2"))
            #expect(FileManager.default.fileExists(atPath: world.copySkillPath("drifty").appendingPathComponent("NOTES.md").path))
        }
    }

    @Test func projectScopeAndIdempotentReenable() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "proj-skill", description: "project scope distribution test")
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: try world.registry())
            let ref = SkillRef(id: "local/src/proj-skill")!

            let project = home.root.appendingPathComponent("my-project", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let out1 = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "sym-agent", project: project)
            #expect(out1.scope == "project")
            #expect(out1.path == project.appendingPathComponent(".agents/skills/proj-skill").path)
            // Enable lại (idempotent) — không lỗi, path giữ nguyên.
            let out2 = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "sym-agent", project: project)
            #expect(out2.path == out1.path)

            let lock = try Lockfile.load(from: home.lockfilePath)
            #expect(lock.skills["local/src/proj-skill"]?.targets.count == 1)
        }
    }

    /// Success criterion #4: thêm agent mới CHỈ bằng file JSON.
    @Test func newAgentByJSONOnly() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let newAgentDir = world.agentRoot.appendingPathComponent("brand-new-agent/skills")
            try FileManager.default.createDirectory(at: newAgentDir, withIntermediateDirectories: true)
            try """
            {
              "schemaVersion": 1, "id": "brand-new-agent", "displayName": "Brand New",
              "detect": ["\(world.agentRoot.path)/brand-new-agent"],
              "skills": {"globalPath": "\(newAgentDir.path)", "projectPath": null,
                         "folderSymlink": true, "fileSymlink": false,
                         "preferredMode": "symlink", "verified": false},
              "mcp": null, "budget": null, "notes": "added by test via JSON only"
            }
            """.write(to: home.adaptersDir.appendingPathComponent("brand-new-agent.json"),
                      atomically: true, encoding: .utf8)

            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "json-only", description: "enabled into adapter defined purely by data")
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: try world.registry())
            let out = try linkEngine.enable(SkillRef(id: "local/src/json-only")!,
                                            sourceId: "local/src", adapterId: "brand-new-agent")
            #expect(out.note?.contains("chưa verified") == true)
            #expect(FileManager.default.fileExists(atPath: newAgentDir.appendingPathComponent("json-only/SKILL.md").path))
        }
    }
}
