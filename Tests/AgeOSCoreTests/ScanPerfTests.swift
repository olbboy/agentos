import Foundation
import Testing
@testable import AgeOSCore

@Suite("Scan performance")
struct ScanPerfTests {
    /// Scanning 500 skills stays under 30s on Apple silicon (including embedding near-duplicate detection).
    @Test(.timeLimit(.minutes(1)))
    func fiveHundredSkillsUnderThirtySeconds() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let dir = world.agentRoot.appendingPathComponent("sym-agent/skills")
            for i in 0..<500 {
                try makeSkillDir(in: dir, name: "perf-skill-\(i)",
                                 description: "Skill number \(i) doing task variant \(i % 37) with topic \(i % 11) for performance measurement purposes.",
                                 body: "# Perf \(i)\nInstructions for variant \(i % 37).\n")
            }
            let engine = try SyncEngine(home: home)
            let started = Date()
            let report = try ScanEngine(home: home, adapters: try world.registry(), index: engine.index).run()
            let elapsed = Date().timeIntervalSince(started)
            #expect(report.scannedSkills == 500)
            #expect(elapsed < 30, "scanning 500 skills took \(elapsed)s — over the 30s budget")
        }
    }
}
