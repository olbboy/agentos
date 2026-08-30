import ArgumentParser
import AgeOSCore
import Foundation

struct AdoptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "adopt",
        abstract: "Inventory skill đang rải rác ở mọi agent; --import để gom vào library."
    )

    @Flag(name: .long, help: "Copy các skill user tự cài vào library (nguồn local/adopted).")
    var `import` = false

    @Flag(name: .long, help: "Xuất JSON.")
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
                print("Effective-load map (\(inventory.totalDistinctSkills) skill distinct, \(inventory.totalLoadEntries) load entries):\n")
                for agent in inventory.agents {
                    let managed = agent.entries.filter(\.managed).count
                    print("● \(agent.adapterId): \(agent.entries.count) skill (\(managed) do AgeOS quản lý)")
                    for (name, paths) in agent.duplicated.sorted(by: { $0.key < $1.key }) {
                        print("  ⚠ '\(name)' bị load từ \(paths.count) path:")
                        for p in paths { print("      \(p)") }
                    }
                }
                let multiAgent = inventory.byName.filter { $0.value.count >= 2 }
                if !multiAgent.isEmpty {
                    print("\n\(multiAgent.count) skill xuất hiện ở ≥2 agent — gom về AgeOS để quản lý 1 chỗ:")
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
                    print("\n✓ Import \(report.imported.count) skill vào nguồn local/adopted (bỏ qua \(report.skippedManaged) bản do AgeOS quản lý)")
                    for e in report.errors { print("  lỗi: \(e)") }
                    if !report.imported.isEmpty {
                        print("  Giờ enable qua AgeOS: ageos enable <tên> --target <agent>")
                    }
                }
            }
        } catch { CLIRuntime.fail(error) }
    }
}

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Quét dupe (exact + near), deprecated, lint trên toàn bộ skill đang load."
    )

    @Option(name: .long, help: "Ngưỡng cosine near-dupe sau mean-centering (mặc định 0.72).")
    var threshold: Double = 0.72

    @Flag(name: .long, help: "Xuất JSON.")
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
                print("Đã quét \(report.scannedSkills) skill (static-only, không execute gì)\n")
                if !report.exactDupes.isEmpty {
                    print("EXACT DUPE (\(report.exactDupes.count) cặp):")
                    for p in report.exactDupes { print("  = \(p.a)\n    \(p.b)") }
                }
                if report.nearDupeAvailable {
                    if !report.nearDupes.isEmpty {
                        print("\nNEAR DUPE (cosine ≥ \(threshold) sau centering):")
                        for p in report.nearDupes.prefix(15) {
                            print("  ≈ [\(String(format: "%.3f", p.score))] \(p.a)\n              \(p.b)")
                        }
                    }
                } else {
                    print("\n(near-dupe bỏ qua — máy thiếu embedding assets)")
                }
                if !report.deprecated.isEmpty {
                    print("\nDEPRECATED (\(report.deprecated.count)):")
                    for d in report.deprecated { print("  ✝ \(d.id) — \(d.reason)") }
                }
                if !report.lintFindings.isEmpty {
                    print("\nLINT (\(report.lintFindings.count) skill có vấn đề description):")
                    for l in report.lintFindings.prefix(10) {
                        print("  ✎ \(l.id): \(l.findings.map(\.rule.rawValue).joined(separator: ", "))")
                    }
                }
                for n in report.notes { print("\nghi chú: \(n)") }
                if report.exactDupes.isEmpty && report.nearDupes.isEmpty && report.deprecated.isEmpty {
                    print("✓ Không dupe, không deprecated")
                }
            }
        } catch { CLIRuntime.fail(error) }
    }
}

struct BudgetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "budget",
        abstract: "Ước lượng token catalog (skills + MCP schemas) mỗi agent gánh (±20%)."
    )

    @Option(name: .long, help: "Adapter id; bỏ trống = mọi adapter phát hiện được.")
    var target: String?

    @Flag(name: .long, help: "Xuất JSON.")
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
                    print("● \(r.adapterId): ≈\(r.totalTokens) tokens luôn-tải (ước lượng ±20%)")
                    print("    skills: \(r.skillCount) × … = ≈\(r.skillTokens) tokens")
                    for top in r.topSkills.prefix(5) { print("      \(top.name): ≈\(top.tokens)") }
                    print("    mcp: \(r.mcpCount) server = ≈\(r.mcpTokens) tokens" +
                          (r.mcpUnknownHealth.isEmpty ? "" : " (+\(r.mcpUnknownHealth.count) chưa đo)"))
                    for w in r.warnings { print("    ⚠ \(w)") }
                    print("")
                }
                print("Đối chiếu thủ công: bật/tắt skill rồi so /context trong agent tương ứng.")
            }
        } catch { CLIRuntime.fail(error) }
    }
}

struct LintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Lint description + validate cấu trúc một skill."
    )

    @Argument(help: "Skill id trong library, hoặc path thư mục skill.")
    var skill: String

    @Flag(name: .long, help: "Xuất JSON.")
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
                print("\(id) — quality \(score.total)/100, phân loại: \(score.classification) [\(score.classificationMethod)]")
                for c in score.explain { print("  \(c.name): \(c.points)/\(c.max) — \(c.note)") }
                if !structural.isEmpty {
                    print("\nCấu trúc:")
                    for s in structural { print("  \(s)") }
                }
                if !lint.isEmpty {
                    print("\nDescription:")
                    for f in lint { print("  ✎ \(f.message)") }
                } else {
                    print("\n✓ Description sạch lint")
                }
            }
        } catch { CLIRuntime.fail(error) }
    }
}

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Tìm skill: library local + index skills.sh (install count)."
    )

    @Argument(help: "Từ khóa.")
    var query: String

    @Flag(name: .long, help: "Xuất JSON.")
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
                    print("\nAdd nguồn: ageos source add https://github.com/<owner>/<repo>")
                } else if local.isEmpty {
                    print("Không có kết quả cho '\(query)'")
                }
            }
        } catch { CLIRuntime.fail(error) }
    }
}
