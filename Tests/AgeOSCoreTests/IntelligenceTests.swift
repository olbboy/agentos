import Foundation
import Testing
@testable import AgeOSCore

@Suite("EffectiveLoadScanner")
struct EffectiveLoadTests {
    /// One skill appearing at 3 paths across 2 agents → the map names all three correctly.
    @Test func mapsDuplicateLoadsAcrossPathsAndAgents() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let shared = home.root.appendingPathComponent("shared-compat/skills", isDirectory: true)
            try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)

            // sym-agent also reads shared (a compat path); copy-agent reads shared too.
            for id in ["sym-agent", "copy-agent"] {
                let path = home.adaptersDir.appendingPathComponent("\(id).json")
                var text = try String(contentsOf: path, encoding: .utf8)
                text = text.replacingOccurrences(
                    of: "\"projectPath\": \".agents/skills\",",
                    with: "\"projectPath\": \".agents/skills\", \"compatPaths\": [\"\(shared.path)\"],")
                try text.write(to: path, atomically: true, encoding: .utf8)
            }

            // The skill "dup-me" lives at: sym-agent global, copy-agent global, and shared compat.
            try makeSkillDir(in: world.agentRoot.appendingPathComponent("sym-agent/skills"),
                             name: "dup-me", description: "duplicated across many load paths for testing")
            try makeSkillDir(in: world.agentRoot.appendingPathComponent("copy-agent/skills"),
                             name: "dup-me", description: "duplicated across many load paths for testing")
            try makeSkillDir(in: shared, name: "dup-me",
                             description: "duplicated across many load paths for testing")
            try makeSkillDir(in: world.agentRoot.appendingPathComponent("sym-agent/skills"),
                             name: "unique-one", description: "only lives in one place for contrast")

            let scanner = EffectiveLoadScanner(adapters: try world.registry())
            let inventory = scanner.scan()

            let sym = inventory.agents.first { $0.adapterId == "sym-agent" }!
            #expect(sym.duplicated["dup-me"]?.count == 2) // global plus compat within the SAME agent
            #expect(inventory.byName["dup-me"]?.sorted() == ["copy-agent", "sym-agent"])
            #expect(inventory.byName["unique-one"] == ["sym-agent"])
            // Total load entries for dup-me across the system = 4 (2 agents × (global + shared compat))
            let totalDupEntries = inventory.agents.flatMap(\.entries).filter { $0.name == "dup-me" }.count
            #expect(totalDupEntries == 4)
        }
    }

    @Test func adoptImportsOnlyUserSkills() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let engine = try SyncEngine(home: home)

            // One skill managed by AgeOS (enabled from the library) plus one the user installed.
            let src = home.root.appendingPathComponent("src")
            try makeSkillDir(in: src, name: "managed-one", description: "installed and managed by ageos")
            _ = try await engine.addSource(src.path)
            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: try world.registry())
            _ = try linkEngine.enable(SkillRef(id: "local/src/managed-one")!,
                                      sourceId: "local/src", adapterId: "copy-agent")
            try makeSkillDir(in: world.agentRoot.appendingPathComponent("sym-agent/skills"),
                             name: "hand-installed", description: "user dropped this in by hand long ago")

            let scanner = EffectiveLoadScanner(adapters: try world.registry())
            let report = try await scanner.adoptImport(home: home, engine: engine)
            #expect(report.imported == ["hand-installed"])
            #expect(report.skippedManaged >= 1)
            // It reached the index through the local/adopted source; the original is untouched.
            let row = try engine.index.findSkill(id: "local/adopted/hand-installed")
            #expect(row != nil)
            #expect(FileManager.default.fileExists(
                atPath: world.agentRoot.appendingPathComponent("sym-agent/skills/hand-installed/SKILL.md").path))
        }
    }
}

@Suite("DedupeEngine calibration")
struct DedupeTests {
    func items() -> [DedupeEngine.Item] {
        [
            .init(id: "a1", name: "image-marketing",
                  description: "Generate marketing images with AI models for product campaigns and social ads.",
                  bodyHead: "# Marketing images\nUse the generator to build campaign visuals, banners and product shots."),
            .init(id: "a2", name: "promo-pictures",
                  description: "Create promotional product pictures using artificial intelligence for campaigns and social media ads.",
                  bodyHead: "# Promo pictures\nBuild campaign visuals, product shots and banner images with the generator."),
            .init(id: "b1", name: "pg-replication",
                  description: "Configure PostgreSQL streaming replication, failover and scheduled backups for production clusters.",
                  bodyHead: "# Postgres replication\nSet up WAL shipping, standby nodes and pg_basebackup schedules."),
            .init(id: "c1", name: "exact-original",
                  description: "Deploy static sites to the edge network quickly.",
                  bodyHead: "# Deploy\nRun the deploy command."),
            .init(id: "c2", name: "exact-original",
                  description: "Deploy   static sites to the edge network quickly.",
                  bodyHead: "# Deploy\n\nRun the   deploy command."),
        ]
    }

    @Test func exactCatchesWhitespaceVariants() {
        let pairs = DedupeEngine().exactDupes(items())
        #expect(pairs.count == 1)
        #expect(pairs[0].a == "c1" && pairs[0].b == "c2")
    }

    /// A near-duplicate pair is caught while an unrelated pair is not a false positive.
    @Test func nearCatchesParaphraseNotDistinct() {
        let engine = DedupeEngine()
        guard let pairs = engine.nearDupes(items()) else {
            // A CI machine has no assets → a deliberate degrade, with exact detection still running.
            return
        }
        let keys = Set(pairs.map { "\($0.a)|\($0.b)" })
        #expect(keys.contains("a1|a2"), "the paraphrase pair must be caught; pairs=\(pairs)")
        #expect(!keys.contains { $0.contains("b1") }, "pg-replication is completely unrelated and must not stick: \(pairs)")
    }
}

@Suite("QualityScorer snapshot")
struct QualityScorerTests {
    @Test func snapshotScoreIsStable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("score-\(UUID().uuidString.prefix(6))/well-made", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("references"),
                                                withIntermediateDirectories: true)
        try """
        ---
        name: well-made
        description: Deploy applications to Cloudflare Workers. Use when the user asks to deploy, publish or ship a Workers project.
        license: MIT
        metadata:
          category: devops
        ---
        # Well made skill
        \(String(repeating: "Detailed instructions line.\n", count: 100))
        """.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let parsed = try SkillParser.parse(directory: dir)
        let fixedNow = Date(timeIntervalSince1970: 1_790_000_000)
        let pushed = Date(timeIntervalSince1970: 1_790_000_000 - 20 * 86_400)
        let score = QualityScorer().score(.init(parsed: parsed, sourceStars: 500,
                                                sourcePushedAt: pushed, sourceLicense: "MIT",
                                                installCount: 12_000), now: fixedNow)
        // Snapshot: metadata 20 + lint 20 + resources 5 + body 10 + stars 12 + fresh 10 + installs 10 = 87
        #expect(score.total == 87, "score drifted: \(score.explain)")
        #expect(score.classification == "devops")
        #expect(score.classificationMethod.contains("keyword"))
    }

    @Test func poorSkillScoresLow() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("poor-\(UUID().uuidString.prefix(6))/helper", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: helper\ndescription: misc helper stuff\n---\nx"
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let parsed = try SkillParser.parse(directory: dir)
        let score = QualityScorer().score(.init(parsed: parsed))
        #expect(score.total < 40, "a threadbare skill must score low: \(score.total)")
    }
}

@Suite("BudgetMeter")
struct BudgetMeterTests {
    @Test func tokenMathAndTruncationAndThreshold() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            // Add a budget block: copy-agent truncates the description at 100 chars, warn threshold 30 tokens (low, to trigger).
            let path = home.adaptersDir.appendingPathComponent("copy-agent.json")
            var text = try String(contentsOf: path, encoding: .utf8)
            text = text.replacingOccurrences(of: "\"budget\": null",
                                             with: "\"budget\": {\"catalogTokensWarn\": 30, \"descriptionTruncateChars\": 100}")
            try text.write(to: path, atomically: true, encoding: .utf8)

            let longDesc = String(repeating: "x", count: 400)
            try makeSkillDir(in: world.agentRoot.appendingPathComponent("copy-agent/skills"),
                             name: "long-desc", description: longDesc)

            let meter = BudgetMeter(adapters: try world.registry())
            let report = try meter.compute(adapterId: "copy-agent")
            // (9 name + min(400,100) desc + 30 overhead) / 4 = 34 tokens
            #expect(report.skillTokens == (9 + 100 + 30) / 4)
            #expect(report.totalTokens > 30)
            #expect(report.warnings.contains { $0.contains("exceeds the") })

            // No truncation (sym-agent): the description keeps all 400.
            try makeSkillDir(in: world.agentRoot.appendingPathComponent("sym-agent/skills"),
                             name: "long-desc", description: longDesc)
            let symReport = try meter.compute(adapterId: "sym-agent")
            #expect(symReport.skillTokens == (9 + 400 + 30) / 4)
        }
    }
}

@Suite("Static-only guarantee")
struct NoExecuteTests {
    /// The scan NEVER spawns a process from a skill's content.
    /// The experimental proxy: a skill carrying a script that writes a marker if it runs → the marker must be absent.
    @Test func scanNeverExecutesSkillContent() async throws {
        try await withTempHome { home in
            let world = try FakeAgentWorld.setUp(home: home)
            let marker = home.root.appendingPathComponent("EXECUTED-MARKER")
            let skillDir = world.agentRoot.appendingPathComponent("sym-agent/skills/booby-trap", isDirectory: true)
            try FileManager.default.createDirectory(at: skillDir.appendingPathComponent("scripts"),
                                                    withIntermediateDirectories: true)
            try """
            ---
            name: booby-trap
            description: Skill with executable payload that must never run during static scan operations.
            ---
            # Trap
            Run scripts/payload.sh
            """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            let payload = skillDir.appendingPathComponent("scripts/payload.sh")
            try "#!/bin/sh\ntouch \(marker.path)\n".write(to: payload, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: payload.path)

            // Run the WHOLE intelligence pipeline over the booby-trapped skill.
            let adapters = try world.registry()
            let engine = try SyncEngine(home: home)
            _ = EffectiveLoadScanner(adapters: adapters).scan()
            _ = try ScanEngine(home: home, adapters: adapters, index: engine.index).run()
            let parsed = try SkillParser.parse(directory: skillDir)
            _ = QualityScorer().score(.init(parsed: parsed))
            _ = try BudgetMeter(adapters: adapters).compute(adapterId: "sym-agent")

            #expect(!FileManager.default.fileExists(atPath: marker.path),
                    "SOMETHING executed the skill's content during the scan!")
        }
    }
}

@Suite("DescriptionLinter")
struct LinterTests {
    @Test func rules() {
        #expect(DescriptionLinter.lint(name: "x", description: "too short").contains { $0.rule == .tooShort })
        #expect(DescriptionLinter.lint(name: "x", description: String(repeating: "a", count: 1100))
            .contains { $0.rule == .tooLong })
        let good = DescriptionLinter.lint(name: "deploy",
            description: "Deploy applications to Cloudflare Workers with wrangler. Use when the user asks to deploy or publish.")
        #expect(good.isEmpty)
        let noTrigger = DescriptionLinter.lint(name: "x",
            description: "A collection of PostgreSQL database administration commands and replication guides.")
        #expect(noTrigger.contains { $0.rule == .noTriggerSignal })
    }
}
