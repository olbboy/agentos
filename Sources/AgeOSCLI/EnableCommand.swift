import ArgumentParser
import AgeOSCore
import Foundation

struct EnableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Enable a skill for one agent (symlink or copy, per the adapter)."
    )

    @Argument(help: "Full skill id (owner/repo/name), or the short name when it is unique.")
    var skill: String

    @Option(name: .long, help: "Adapter id (e.g. claude-code, codex — see `ageos targets list`).")
    var target: String

    @Option(name: .long, help: "Project path, to enable at project scope instead of globally.")
    var project: String?

    @Option(name: .long, help: "Force a mode: symlink | copy (defaults to the adapter's).")
    var mode: String?

    @Flag(name: .long, help: "Emit JSON.")
    var json = false

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            let row = try engine.index.resolveSkill(query: skill)
            guard let ref = SkillRef(id: row.id) else {
                throw AgeOSError(.notFound, "Invalid skill id in the index: \(row.id)")
            }
            let adapters = try AdapterRegistry(home: engine.home)
            let linkEngine = LinkEngine(home: engine.home, store: engine.store, adapters: adapters)
            let modeOverride: AdapterSpec.LinkModeSpec? = try mode.map {
                guard let m = AdapterSpec.LinkModeSpec(rawValue: $0) else {
                    throw AgeOSError(.unsupported, "'\($0)' is not a valid mode", remedy: "Use symlink or copy")
                }
                return m
            }
            let projectURL = project.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            let outcome = try linkEngine.enable(ref, sourceId: row.sourceId, adapterId: target,
                                               project: projectURL, modeOverride: modeOverride)
            if json {
                CLIRuntime.printJSON(outcome)
            } else {
                print("✓ \(outcome.skillId) → \(outcome.adapterId) [\(outcome.scope), \(outcome.mode)]")
                print("  \(outcome.path)")
                if let note = outcome.note { print("  ⚠ \(note)") }
                if row.deprecated { print("  ⚠ this skill is marked deprecated") }
            }
        } catch { CLIRuntime.fail(error) }
    }
}

struct DisableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Remove a skill from one agent (only removes what AgeOS created)."
    )

    @Argument(help: "Skill id, or the short name.")
    var skill: String

    @Option(name: .long, help: "Adapter id.")
    var target: String

    @Option(name: .long, help: "Project path, if it was enabled at project scope.")
    var project: String?

    @Flag(name: .long, help: "Emit JSON.")
    var json = false

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            // Disable does not require the skill to still be in the index — resolve leniently via the lockfile.
            let lock = try Lockfile.load(from: engine.home.lockfilePath)
            let id: String
            if lock.skills[skill] != nil {
                id = skill
            } else {
                let matches = lock.skills.keys.filter { $0.hasSuffix("/\(skill)") }
                switch matches.count {
                case 1: id = matches[0]
                case 0:
                    throw AgeOSError(.notFound, "'\(skill)' is not in the lockfile",
                                     remedy: "Run `ageos doctor` to see the current enable state")
                default:
                    throw AgeOSError(.conflict, "'\(skill)' matches several: \(matches.sorted().joined(separator: ", "))",
                                     remedy: "Use the full id")
                }
            }
            guard let ref = SkillRef(id: id) else {
                throw AgeOSError(.notFound, "Invalid id: \(id)")
            }
            let adapters = try AdapterRegistry(home: engine.home)
            let linkEngine = LinkEngine(home: engine.home, store: engine.store, adapters: adapters)
            let projectURL = project.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            let outcome = try linkEngine.disable(ref, adapterId: target, project: projectURL)
            if json {
                CLIRuntime.printJSON(outcome)
            } else {
                print("✓ Removed \(outcome.skillId) from \(outcome.adapterId) [\(outcome.scope)]")
                if let note = outcome.note { print("  \(note)") }
            }
        } catch { CLIRuntime.fail(error) }
    }
}
