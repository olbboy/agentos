import Foundation
import Testing
@testable import AgeOSCore

@Suite("Scan performance")
struct ScanPerfTests {
    /// Non-functional Phase 5: scan 500 skills < 30s trên M-series (gồm cả embedding near-dupe).
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
            #expect(elapsed < 30, "scan 500 skills mất \(elapsed)s — vượt ngân sách 30s")
        }
    }
}
