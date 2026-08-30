import ArgumentParser
import AgeOSCore
import Foundation

struct AdoptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "adopt",
        abstract: "Inventory the skills scattered across every agent; --import to gather them into the library."
    )

    @Flag(name: .long, help: "Copy the skills you installed yourself into the library (local/adopted source).")
    var `import` = false

    @Flag(name: .long, help: "Emit JSON.")
    var json = false

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            let adapters = try AdapterRegistry(home: engine.home)
            let scanner = EffectiveLoadScanner(adapters: adapters)
            let inventory = scanner.scan()

            if json && !`import` {
                CLIRuntime.printJSON(inventory)
            } else {
                print("Effective-load map (\(CLIRuntime.count(inventory.totalDistinctSkills, "distinct skill")), \(CLIRuntime.count(inventory.totalLoadEntries, "load entry", plural: "load entries"))):\n")
                for agent in inventory.agents {
                    let managed = agent.entries.filter(\.managed).count
                    print("● \(agent.adapterId): \(CLIRuntime.count(agent.entries.count, "skill")) (\(managed) managed by AgeOS)")
                    for (name, paths) in agent.duplicated.sorted(by: { $0.key < $1.key }) {
                        print("  ⚠ '\(name)' is loaded from \(CLIRuntime.count(paths.count, "path")):")
                        for p in paths { print("      \(p)") }
                    }
                }
                let multiAgent = inventory.byName.filter { $0.value.count >= 2 }
                if !multiAgent.isEmpty {
                    print("\n\(CLIRuntime.count(multiAgent.count, "skill")) appear in 2 or more agents — gather them into AgeOS to manage them in one place:")
                    for (name, agentIds) in multiAgent.sorted(by: { $0.value.count > $1.value.count }).prefix(10) {
                        print("  \(name) → \(agentIds.sorted().joined(separator: ", "))")
                    }
                }
            }

            if `import` {
                let report = try await scanner.adoptImport(home: engine.home, engine: engine)
                if json {
                    CLIRuntime.printJSON(report)
                } else {
                    print("\n✓ Imported \(CLIRuntime.count(report.imported.count, "skill")) into the local/adopted source (skipped \(report.skippedManaged) already managed by AgeOS)")
                    for e in report.errors { print("  error: \(e)") }
                    if !report.imported.isEmpty {
                        print("  Now enable them through AgeOS: ageos enable <name> --target <agent>")
                    }
                }
            }
        } catch { CLIRuntime.fail(error) }
    }
}

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan every loaded skill for duplicates (exact + near), deprecation, and lint issues."
    )

    @Option(name: .long, help: "Cosine threshold for near-duplicates after mean-centering (default 0.72).")
    var threshold: Double = 0.72

    @Flag(name: .long, help: "Emit JSON.")
    var json = false

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            let adapters = try AdapterRegistry(home: engine.home)
            let scanEngine = ScanEngine(home: engine.home, adapters: adapters, index: engine.index,
                                        dedupe: DedupeEngine(nearThreshold: threshold))
            let report = try scanEngine.run()
            if json {
                CLIRuntime.printJSON(report)
            } else {
                print("Scanned \(CLIRuntime.count(report.scannedSkills, "skill")) (static-only, nothing was executed)\n")
                if !report.exactDupes.isEmpty {
                    print("EXACT DUPLICATES (\(CLIRuntime.count(report.exactDupes.count, "pair"))):")
                    for p in report.exactDupes { print("  = \(p.a)\n    \(p.b)") }
                }
                if report.nearDupeAvailable {
                    if !report.nearDupes.isEmpty {
                        print("\nNEAR DUPLICATES (cosine ≥ \(threshold) after centering):")
                        for p in report.nearDupes.prefix(15) {
                            print("  ≈ [\(String(format: "%.3f", p.score))] \(p.a)\n              \(p.b)")
                        }
                    }
                } else {
                    print("\n(near-duplicate detection skipped — this machine has no embedding assets)")
                }
                if !report.deprecated.isEmpty {
                    print("\nDEPRECATED (\(report.deprecated.count)):")
                    for d in report.deprecated { print("  ✝ \(d.id) — \(d.reason)") }
                }
                if !report.lintFindings.isEmpty {
                    print("\nLINT (\(CLIRuntime.count(report.lintFindings.count, "skill")) with description problems):")
                    for l in report.lintFindings.prefix(10) {
                        print("  ✎ \(l.id): \(l.findings.map(\.rule.rawValue).joined(separator: ", "))")
                    }
                }
                for n in report.notes { print("\nnote: \(n)") }
                if report.exactDupes.isEmpty && report.nearDupes.isEmpty && report.deprecated.isEmpty {
                    print("✓ No duplicates, nothing deprecated")
                }
            }
        } catch { CLIRuntime.fail(error) }
    }
}

struct BudgetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "budget",
        abstract: "Estimate the catalog tokens (skills + MCP schemas) each agent carries (±20%)."
    )

    @Option(name: .long, help: "Adapter id; leave empty for every detected adapter.")
    var target: String?

    @Flag(name: .long, help: "Emit JSON.")
    var json = false

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            let adapters = try AdapterRegistry(home: engine.home)
            let index = engine.index
            let meter = BudgetMeter(adapters: adapters,
                                    mcpSchemaTokens: { name in try? index.mcpSchemaTokens(entryName: name) })
            let ids = target.map { [$0] } ?? adapters.detected().filter { $0.skills != nil || $0.mcp != nil }.map(\.id)
            var reports: [BudgetMeter.Report] = []
            for id in ids {
                reports.append(try meter.compute(adapterId: id))
            }
            if json {
                CLIRuntime.printJSON(reports)
            } else {
                for r in reports {
                    print("● \(r.adapterId): ≈\(r.totalTokens) always-loaded tokens (±20% estimate)")
                    print("    skills: \(r.skillCount) × … = ≈\(r.skillTokens) tokens")
                    for top in r.topSkills.prefix(5) { print("      \(top.name): ≈\(top.tokens)") }
                    print("    mcp: \(CLIRuntime.count(r.mcpCount, "server")) = ≈\(r.mcpTokens) tokens" +
                          (r.mcpUnknownHealth.isEmpty ? "" : " (+\(r.mcpUnknownHealth.count) not measured)"))
                    for w in r.warnings { print("    ⚠ \(w)") }
                    print("")
                }
                print("To check by hand: toggle a skill on and off, then compare /context in that agent.")
            }
        } catch { CLIRuntime.fail(error) }
    }
}

struct LintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Lint the description and validate the structure of one skill."
    )

    @Argument(help: "Skill id in the library, or a path to a skill folder.")
    var skill: String

    @Flag(name: .long, help: "Emit JSON.")
    var json = false

    struct Output: Codable {
        var id: String
        var structuralIssues: [String]
        var lintFindings: [DescriptionLinter.Finding]
        var qualityScore: QualityScorer.Score
    }

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            let dir: URL
            var id = skill
            let asPath = URL(fileURLWithPath: (skill as NSString).expandingTildeInPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: asPath.appendingPathComponent("SKILL.md").path) {
                dir = asPath
            } else {
                let row = try engine.index.resolveSkill(query: skill)
                id = row.id
                dir = URL(fileURLWithPath: row.path, isDirectory: true)
            }
            let parsed = try SkillParser.parse(directory: dir)
            let structural = SkillValidator.validate(parsed).map(\.description)
            let lint = DescriptionLinter.lint(name: parsed.manifest.name, description: parsed.manifest.description)
            let sources = try engine.registry.load()
            let source = sources.first { parsed.directory.path.contains($0.namespace) }
            let score = QualityScorer().score(.init(parsed: parsed, sourceStars: source?.stars,
                                                    sourcePushedAt: source?.pushedAt,
                                                    sourceLicense: source?.license))
            let output = Output(id: id, structuralIssues: structural, lintFindings: lint, qualityScore: score)
            if json {
                CLIRuntime.printJSON(output)
            } else {
                print("\(id) — quality \(score.total)/100, classified as: \(score.classification) [\(score.classificationMethod)]")
                for c in score.explain { print("  \(c.name): \(c.points)/\(c.max) — \(c.note)") }
                if !structural.isEmpty {
                    print("\nStructure:")
                    for s in structural { print("  \(s)") }
                }
                if !lint.isEmpty {
                    print("\nDescription:")
                    for f in lint { print("  ✎ \(f.message)") }
                } else {
                    print("\n✓ Description passes lint")
                }
            }
        } catch { CLIRuntime.fail(error) }
    }
}

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search for skills: your local library plus the skills.sh index (install counts)."
    )

    @Argument(help: "Keyword.")
    var query: String

    @Flag(name: .long, help: "Emit JSON.")
    var json = false

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            let local = try engine.index.listSkills().filter {
                $0.id.localizedCaseInsensitiveContains(query)
                    || $0.description.localizedCaseInsensitiveContains(query)
            }
            let remote = await SkillsShSource().search(query)
            if json {
                struct Combined: Codable {
                    var local: [[String: String]]
                    var skillsSh: [SkillsShSource.Hit]
                }
                CLIRuntime.printJSON(Combined(
                    local: local.map { ["id": $0.id, "description": $0.description] },
                    skillsSh: remote))
            } else {
                if !local.isEmpty {
                    print("LIBRARY (\(local.count)):")
                    for s in local.prefix(10) { print("  \(s.id)") }
                }
                if !remote.isEmpty {
                    print("\nSKILLS.SH:")
                    for h in remote.prefix(10) {
                        print("  \(h.id) — \(h.installs) installs")
                    }
                    print("\nAdd a source: ageos source add https://github.com/<owner>/<repo>")
                } else if local.isEmpty {
                    print("No results for '\(query)'")
                }
            }
        } catch { CLIRuntime.fail(error) }
    }
}
