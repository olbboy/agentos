import ArgumentParser
import AgeOSCore
import Foundation

struct EnableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Enable skill cho một agent (symlink hoặc copy theo adapter)."
    )

    @Argument(help: "Skill id đầy đủ (owner/repo/name) hoặc tên ngắn nếu duy nhất.")
    var skill: String

    @Option(name: .long, help: "Adapter id (vd claude-code, codex — xem `ageos targets list`).")
    var target: String

    @Option(name: .long, help: "Path project để enable scope project thay vì global.")
    var project: String?

    @Option(name: .long, help: "Ép mode: symlink | copy (mặc định theo adapter).")
    var mode: String?

    @Flag(name: .long, help: "Xuất JSON.")
    var json = false

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            let row = try engine.index.resolveSkill(query: skill)
            guard let ref = SkillRef(id: row.id) else {
                throw AgeOSError(.notFound, "Id skill không hợp lệ trong index: \(row.id)")
            }
            let adapters = try AdapterRegistry(home: engine.home)
            let linkEngine = LinkEngine(home: engine.home, store: engine.store, adapters: adapters)
            let modeOverride: AdapterSpec.LinkModeSpec? = try mode.map {
                guard let m = AdapterSpec.LinkModeSpec(rawValue: $0) else {
                    throw AgeOSError(.unsupported, "Mode '\($0)' không hợp lệ", remedy: "Dùng symlink hoặc copy")
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
                if row.deprecated { print("  ⚠ skill đang bị đánh dấu deprecated") }
            }
        } catch { CLIRuntime.fail(error) }
    }
}

struct DisableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Gỡ skill khỏi một agent (chỉ gỡ thứ AgeOS đã tạo)."
    )

    @Argument(help: "Skill id hoặc tên ngắn.")
    var skill: String

    @Option(name: .long, help: "Adapter id.")
    var target: String

    @Option(name: .long, help: "Path project nếu enable ở scope project.")
    var project: String?

    @Flag(name: .long, help: "Xuất JSON.")
    var json = false

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            // Disable không bắt buộc skill còn trong index — resolve mềm qua lockfile.
            let lock = try Lockfile.load(from: engine.home.lockfilePath)
            let id: String
            if lock.skills[skill] != nil {
                id = skill
            } else {
                let matches = lock.skills.keys.filter { $0.hasSuffix("/\(skill)") }
                switch matches.count {
                case 1: id = matches[0]
                case 0:
                    throw AgeOSError(.notFound, "'\(skill)' không có trong lockfile",
                                     remedy: "Xem `ageos doctor` để thấy trạng thái enable hiện tại")
                default:
                    throw AgeOSError(.conflict, "'\(skill)' khớp nhiều: \(matches.sorted().joined(separator: ", "))",
                                     remedy: "Dùng id đầy đủ")
                }
            }
            guard let ref = SkillRef(id: id) else {
                throw AgeOSError(.notFound, "Id không hợp lệ: \(id)")
            }
            let adapters = try AdapterRegistry(home: engine.home)
            let linkEngine = LinkEngine(home: engine.home, store: engine.store, adapters: adapters)
            let projectURL = project.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            let outcome = try linkEngine.disable(ref, adapterId: target, project: projectURL)
            if json {
                CLIRuntime.printJSON(outcome)
            } else {
                print("✓ Đã gỡ \(outcome.skillId) khỏi \(outcome.adapterId) [\(outcome.scope)]")
                if let note = outcome.note { print("  \(note)") }
            }
        } catch { CLIRuntime.fail(error) }
    }
}
