import Foundation
import Testing
@testable import AgeOSCore

@Suite("Doctor phát hiện + sửa drift")
struct DoctorTests {
    /// Success criterion #3 Phase 3: doctor phát hiện + sửa link gãy, copy drift, orphan.
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
            // 1) Làm gãy symlink: xóa đích trong agent dir? Không — xóa store version → link gãy.
            //    (removeItem trên store dir; current symlink trong store cũng chết theo)
            //    Đơn giản hơn: xóa chính symlink đích → missing_target.
            try fm.removeItem(at: world.symSkillPath("sym-victim"))
            // 2) Drift copy: sửa file trong bản copy.
            try "hacked".write(to: world.copySkillPath("copy-victim").appendingPathComponent("SKILL.md"),
                               atomically: true, encoding: .utf8)
            // 3) Orphan: dir có marker AgeOS nhưng không có trong lockfile.
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

            // --fix: tái tạo link, re-copy, dọn orphan.
            let fixedFindings = try doctor.run(fix: true)
            #expect(fixedFindings.filter(\.fixed).count >= 3)
            #expect(fm.fileExists(atPath: world.symSkillPath("sym-victim").appendingPathComponent("SKILL.md").path))
            let repaired = try SkillParser.parse(directory: world.copySkillPath("copy-victim"))
            #expect(repaired.manifest.description.contains("gets edited"))
            #expect(!fm.fileExists(atPath: orphan.path))

            // Sau fix, doctor sạch.
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

            // User xóa symlink của AgeOS, đặt dir thường của họ vào (không marker).
            let dest = world.symSkillPath("shadowed")
            try FileManager.default.removeItem(at: dest)
            try makeSkillDir(in: dest.deletingLastPathComponent(), name: "shadowed",
                             description: "user replacement — doctor must not delete")

            let doctor = Doctor(home: home, store: engine.store, adapters: registry)
            let findings = try doctor.run(fix: true)
            #expect(findings.contains { $0.kind == .userShadow })
            // Đồ user sống sót qua --fix.
            let alive = try SkillParser.parse(directory: dest)
            #expect(alive.manifest.description.contains("user replacement"))
        }
    }
}
