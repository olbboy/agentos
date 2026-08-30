import Foundation
import Testing
@testable import AgeOSCore

/// Regression tests cho các finding của code review 30/8/2026.
/// Mỗi test tương ứng một bug ĐÃ TỪNG TỒN TẠI — không được xanh trên code cũ.
@Suite("Review regressions")
struct ReviewRegressionTests {
    /// Critical: isOurs từng so path lockfile với chính nó (hằng-đúng) →
    /// disable xóa nhầm thư mục user thay chỗ symlink AgeOS.
    @Test func disableRefusesUserReplacedContent() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "swapped", description: "skill whose symlink user replaces with own dir")
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: try world.registry())
            let ref = SkillRef(id: "local/src/swapped")!
            _ = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "sym-agent")

            // User: xóa symlink AgeOS, đặt thư mục THẬT của họ vào đúng chỗ (không marker).
            let dest = world.symSkillPath("swapped")
            try FileManager.default.removeItem(at: dest)
            try makeSkillDir(in: dest.deletingLastPathComponent(), name: "swapped",
                             description: "precious user content that must survive disable")

            do {
                _ = try linkEngine.disable(ref, adapterId: "sym-agent")
                Issue.record("disable phải từ chối khi đích không phải của AgeOS")
            } catch let error as AgeOSError {
                #expect(error.code == .conflict)
            }
            // Đồ user sống sót.
            let survived = try SkillParser.parse(directory: dest)
            #expect(survived.manifest.description.contains("precious user content"))
        }
    }

    /// Cùng lớp bug ở phía enable: re-enable khi user đã thay đích phải CHẶN, không đè.
    @Test func reenableRefusesUserReplacedContent() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "retaken", description: "skill user reclaims by hand after enable")
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: try world.registry())
            let ref = SkillRef(id: "local/src/retaken")!
            _ = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "sym-agent")

            let dest = world.symSkillPath("retaken")
            try FileManager.default.removeItem(at: dest)
            try makeSkillDir(in: dest.deletingLastPathComponent(), name: "retaken",
                             description: "user replacement must block re-enable")

            #expect(throws: AgeOSError.self) {
                _ = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "sym-agent")
            }
            let survived = try SkillParser.parse(directory: dest)
            #expect(survived.manifest.description.contains("must block re-enable"))
        }
    }

    /// Propagate copy-mode: đích mất manifest (user thay) → bỏ qua + cảnh báo, không re-copy đè.
    @Test func propagateSkipsUserReplacedCopy() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "taken-copy", description: "copy dir user fully replaced v1")
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: try world.registry())
            let ref = SkillRef(id: "local/src/taken-copy")!
            _ = try linkEngine.enable(ref, sourceId: "local/src", adapterId: "copy-agent")

            // User thay TOÀN BỘ bản copy (mất manifest + marker).
            let dest = world.copySkillPath("taken-copy")
            try FileManager.default.removeItem(at: dest)
            try makeSkillDir(in: dest.deletingLastPathComponent(), name: "taken-copy",
                             description: "fully user-owned now, no manifest")

            // Nguồn ra version mới → sync → KHÔNG được đè.
            try "---\nname: taken-copy\ndescription: upstream v2 that must not clobber\n---\nx"
                .write(to: src.appendingPathComponent("taken-copy/SKILL.md"), atomically: true, encoding: .utf8)
            let reports = try await engine.sync()
            #expect(reports[0].driftWarnings.contains { $0.contains("mất manifest") })
            let onDisk = try SkillParser.parse(directory: dest)
            #expect(onDisk.manifest.description.contains("fully user-owned"))
        }
    }

    /// High: lockfile RMW race — N enable đồng thời (mô phỏng CLI + ageos-mcp song song)
    /// không được đánh mất entry nào nhờ flock.
    @Test func concurrentEnablesKeepAllLockfileEntries() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let src = home.root.appendingPathComponent("src")
            let count = 8
            for i in 0..<count {
                try makeSkillDir(in: src, name: "race-\(i)", description: "concurrent enable target number \(i)")
            }
            let engine = try SyncEngine(home: home)
            _ = try await engine.addSource(src.path)
            let registry = try world.registry()

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<count {
                    group.addTask {
                        let linkEngine = LinkEngine(home: home, store: Store(home: home), adapters: registry)
                        _ = try? linkEngine.enable(SkillRef(id: "local/src/race-\(i)")!,
                                                   sourceId: "local/src", adapterId: "sym-agent")
                    }
                }
            }

            let lock = try Lockfile.load(from: home.lockfilePath)
            #expect(lock.skills.count == count,
                    "mất entry vì race: còn \(lock.skills.count)/\(count) — \(lock.skills.keys.sorted())")
        }
    }

    /// Medium: server chết ngay sau spawn → health fail NHANH, không đợi trọn timeout.
    @Test func earlyCrashFailsFast() {
        let launch = McpServerModel.Launch(transport: .stdio, command: "/usr/bin/false", args: [])
        let started = Date()
        let report = HealthCheck.run(launch, timeout: 10)
        let elapsed = Date().timeIntervalSince(started)
        #expect(!report.ok)
        #expect(elapsed < 5, "crash sớm mà tốn \(elapsed)s — phải fail nhanh qua EOF")
    }

    /// Medium: cơ chế near-dupe (centering + threshold + pairing) phải test được
    /// DETERMINISTIC không cần embedding assets (chống phantom test trên CI).
    @Test func nearDupeMechanismWithSyntheticVectors() {
        let items = [
            DedupeEngine.Item(id: "s1", name: "a", description: "d", bodyHead: ""),
            DedupeEngine.Item(id: "s2", name: "b", description: "d", bodyHead: ""),
            DedupeEngine.Item(id: "s3", name: "c", description: "d", bodyHead: ""),
            DedupeEngine.Item(id: "s4", name: "e", description: "d", bodyHead: ""),
        ]
        // Anisotropy nhân tạo: mọi vector chung offset lớn [10,10,10];
        // s1↔s2 gần nhau, s3 lệch hướng khác, s4 trung tính.
        let vectors: [[Double]] = [
            [10.9, 10.1, 10.0],
            [10.8, 10.2, 10.0],
            [10.0, 10.9, 10.8],
            [10.3, 10.4, 10.5],
        ]
        // Raw cosine (không centering) coi mọi cặp là ~1.0 — kiểm chứng tiền đề spike:
        #expect(DedupeEngine.cosine(vectors[0], vectors[2]) > 0.99)

        let pairs = DedupeEngine(nearThreshold: 0.9).nearDupes(items, precomputedVectors: vectors)
        let keys = Set((pairs ?? []).map { "\($0.a)|\($0.b)" })
        #expect(keys.contains("s1|s2"), "cặp gần nhau sau centering phải bị bắt: \(keys)")
        #expect(!keys.contains("s1|s3"), "cặp lệch hướng không được dính: \(keys)")
    }
}
