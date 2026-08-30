import Foundation
import Testing
@testable import AgeOSCore

@Suite("Doctor finds and repairs drift")
struct DoctorTests {
    /// Doctor finds and repairs broken links, copy drift and orphans.
    @Test func detectsAndFixesBrokenLinkDriftAndOrphan() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "sym-victim", description: "skill whose store gets nuked")
            try makeSkillDir(in: src, name: "copy-victim", description: "skill whose copy gets edited")
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            let registry = try world.registry()
            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: registry)
            let symRef = SkillRef(id: "local/src/sym-victim")!
            let copyRef = SkillRef(id: "local/src/copy-victim")!
            _ = try linkEngine.enable(symRef, sourceId: "local/src", adapterId: "sym-agent")
            _ = try linkEngine.enable(copyRef, sourceId: "local/src", adapterId: "copy-agent")

            let fm = FileManager.default
            // 1) Break the symlink. Not by deleting the destination in the agent dir — deleting
            //    the store version kills the link too (the store's own current symlink dies with it).
            //    Simpler: delete the destination symlink itself → missing_target.
            try fm.removeItem(at: world.symSkillPath("sym-victim"))
            // 2) Copy drift: edit a file inside the copy.
            try "hacked".write(to: world.copySkillPath("copy-victim").appendingPathComponent("SKILL.md"),
                               atomically: true, encoding: .utf8)
            // 3) Orphan: a directory carrying the AgeOS marker that the lockfile does not know.
            let orphan = world.agentRoot.appendingPathComponent("sym-agent/skills/orphan-dir")
            try fm.createDirectory(at: orphan, withIntermediateDirectories: true)
            ManagedMarker.set(on: orphan.path)

            let doctor = Doctor(home: home, store: engine.store, adapters: registry)
            let findings = try doctor.run(fix: false)
            let kinds = Set(findings.map(\.kind))
            #expect(kinds.contains(.missingTarget))
            #expect(kinds.contains(.copyDrift))
            #expect(kinds.contains(.orphanFile))
            #expect(findings.allSatisfy { !$0.fixed })

            // --fix: recreate the link, re-copy, clean the orphan.
            let fixedFindings = try doctor.run(fix: true)
            #expect(fixedFindings.filter(\.fixed).count >= 3)
            #expect(fm.fileExists(atPath: world.symSkillPath("sym-victim").appendingPathComponent("SKILL.md").path))
            let repaired = try SkillParser.parse(directory: world.copySkillPath("copy-victim"))
            #expect(repaired.manifest.description.contains("gets edited"))
            #expect(!fm.fileExists(atPath: orphan.path))

            // After the fix, doctor comes back clean.
            let clean = try doctor.run(fix: false)
            #expect(clean.isEmpty)
        }
    }

    @Test func userShadowIsReportedNotTouched() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "shadowed", description: "skill user replaces by hand")
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            let registry = try world.registry()
            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: registry)
            let ref = SkillRef(id: "local/src/shadowed")!
            _ = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "sym-agent")

            // The user deleted the AgeOS symlink and put their own plain directory there (no marker).
            let dest = world.symSkillPath("shadowed")
            try FileManager.default.removeItem(at: dest)
            try makeSkillDir(in: dest.deletingLastPathComponent(), name: "shadowed",
                             description: "user replacement — doctor must not delete")

            let doctor = Doctor(home: home, store: engine.store, adapters: registry)
            let findings = try doctor.run(fix: true)
            #expect(findings.contains { $0.kind == .userShadow })
            // The user's files survive --fix.
            let alive = try SkillParser.parse(directory: dest)
            #expect(alive.manifest.description.contains("user replacement"))
        }
    }
}
