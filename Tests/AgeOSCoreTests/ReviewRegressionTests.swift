import Foundation
import Testing
@testable import AgeOSCore

/// Regression tests for the findings of a code review.
/// Each one corresponds to a bug that ONCE EXISTED — none of them may pass against the old code.
@Suite("Review regressions")
struct ReviewRegressionTests {
    /// Critical: isOurs used to compare a lockfile path against itself (always true), so
    /// disable deleted a user's directory that had replaced an AgeOS symlink.
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

            // The user deletes the AgeOS symlink and puts their OWN real directory in its place (no marker).
            let dest = world.symSkillPath("swapped")
            try FileManager.default.removeItem(at: dest)
            try makeSkillDir(in: dest.deletingLastPathComponent(), name: "swapped",
                             description: "precious user content that must survive disable")

            do {
                _ = try linkEngine.disable(ref, adapterId: "sym-agent")
                Issue.record("disable must refuse when the destination does not belong to AgeOS")
            } catch let error as AgeOSError {
                #expect(error.code == .conflict)
            }
            // The user's files survive.
            let survived = try SkillParser.parse(directory: dest)
            #expect(survived.manifest.description.contains("precious user content"))
        }
    }

    /// The same class of bug on the enable side: re-enabling over a destination the user replaced must STOP, not overwrite.
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

    /// Copy-mode propagation: a destination missing its manifest (the user replaced it) → skip and warn, never re-copy over it.
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

            // The user replaces the ENTIRE copy (losing the manifest and marker).
            let dest = world.copySkillPath("taken-copy")
            try FileManager.default.removeItem(at: dest)
            try makeSkillDir(in: dest.deletingLastPathComponent(), name: "taken-copy",
                             description: "fully user-owned now, no manifest")

            // The source produces a new version → sync → it must NOT overwrite.
            try "---\nname: taken-copy\ndescription: upstream v2 that must not clobber\n---\nx"
                .write(to: src.appendingPathComponent("taken-copy/SKILL.md"), atomically: true, encoding: .utf8)
            let reports = try await engine.sync()
            #expect(reports[0].driftWarnings.contains { $0.contains("no AgeOS manifest") })
            let onDisk = try SkillParser.parse(directory: dest)
            #expect(onDisk.manifest.description.contains("fully user-owned"))
        }
    }

    /// High: a lockfile read-modify-write race — N concurrent enables (simulating the CLI and
    /// ageos-mcp running side by side) must not lose a single entry, thanks to flock.
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
                    "entries lost to a race: \(lock.skills.count)/\(count) remain — \(lock.skills.keys.sorted())")
        }
    }

    /// Medium: a server dying right after spawn → health fails FAST, without waiting out the timeout.
    @Test func earlyCrashFailsFast() {
        let launch = McpServerModel.Launch(transport: .stdio, command: "/usr/bin/false", args: [])
        let started = Date()
        let report = HealthCheck.run(launch, timeout: 10)
        let elapsed = Date().timeIntervalSince(started)
        #expect(!report.ok)
        #expect(elapsed < 5, "an early crash took \(elapsed)s — it must fail fast on EOF")
    }

    /// Medium: the near-duplicate mechanism (centering, threshold, pairing) has to be testable
    /// DETERMINISTICALLY without embedding assets, so CI does not run a phantom test.
    @Test func nearDupeMechanismWithSyntheticVectors() {
        let items = [
            DedupeEngine.Item(id: "s1", name: "a", description: "d", bodyHead: ""),
            DedupeEngine.Item(id: "s2", name: "b", description: "d", bodyHead: ""),
            DedupeEngine.Item(id: "s3", name: "c", description: "d", bodyHead: ""),
            DedupeEngine.Item(id: "s4", name: "e", description: "d", bodyHead: ""),
        ]
        // Artificial anisotropy: every vector shares a large [10,10,10] offset;
        // s1 and s2 sit close together, s3 points elsewhere, s4 is neutral.
        let vectors: [[Double]] = [
            [10.9, 10.1, 10.0],
            [10.8, 10.2, 10.0],
            [10.0, 10.9, 10.8],
            [10.3, 10.4, 10.5],
        ]
        // Raw cosine (without centering) rates every pair at ~1.0 — this verifies the spike's premise:
        #expect(DedupeEngine.cosine(vectors[0], vectors[2]) > 0.99)

        let pairs = DedupeEngine(nearThreshold: 0.9).nearDupes(items, precomputedVectors: vectors)
        let keys = Set((pairs ?? []).map { "\($0.a)|\($0.b)" })
        #expect(keys.contains("s1|s2"), "a pair that is close after centering must be caught: \(keys)")
        #expect(!keys.contains("s1|s3"), "a pair pointing elsewhere must not stick: \(keys)")
    }
}
