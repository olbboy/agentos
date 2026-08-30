import ArgumentParser
import AgeOSCore
import Foundation

struct TargetsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "targets",
        abstract: "Adapter khả dụng và trạng thái phát hiện trên máy.",
        subcommands: [List.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Liệt kê adapter.")

        @Flag(name: .long, help: "Xuất JSON.")
        var json = false

        struct Row: Codable {
            var id: String
            var displayName: String
            var detected: Bool
            var skills: Bool
            var mcp: Bool
            var preferredMode: String?
            var verified: Bool
        }

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let registry = try AdapterRegistry(home: engine.home)
                let rows = registry.adapters.map { a in
                    Row(id: a.id, displayName: a.displayName, detected: a.isDetected(),
                        skills: a.skills != nil, mcp: a.mcp != nil,
                        preferredMode: a.skills.map { _ in a.effectiveSkillMode.rawValue },
                        verified: (a.skills?.verified ?? a.mcp?.verified) ?? false)
                }
                if json {
                    CLIRuntime.printJSON(rows)
                } else {
                    for r in rows {
                        let mark = r.detected ? "●" : "○"
                        var caps: [String] = []
                        if r.skills { caps.append("skills(\(r.preferredMode ?? "?"))") }
                        if r.mcp { caps.append("mcp") }
                        let verified = r.verified ? "" : " [chưa verified]"
                        print("\(mark) \(r.id) — \(r.displayName): \(caps.joined(separator: ", "))\(verified)")
                    }
                    print("\n● = phát hiện trên máy này")
                }
            } catch { CLIRuntime.fail(error) }
        }
    }
}

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Khám drift lockfile ↔ filesystem; --fix để sửa."
    )

    @Flag(name: .long, help: "Sửa các finding sửa được (re-link, re-copy, dọn orphan).")
    var fix = false

    @Flag(name: .long, help: "Xuất JSON.")
    var json = false

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            let adapters = try AdapterRegistry(home: engine.home)
            let doctor = Doctor(home: engine.home, store: engine.store, adapters: adapters)
            let findings = try doctor.run(fix: fix)
            if json {
                CLIRuntime.printJSON(findings)
            } else if findings.isEmpty {
                print("✓ Không phát hiện vấn đề nào — lockfile khớp filesystem")
            } else {
                for f in findings {
                    let status = f.fixed ? "✔ FIXED" : (f.fixable ? "✗ (sửa được với --fix)" : "⚠")
                    print("\(status) [\(f.kind.rawValue)] \(f.skillId ?? "-") \(f.targetKey.map { "(\($0))" } ?? "")")
                    print("    \(f.path)")
                    print("    \(f.message)")
                }
                let fixable = findings.filter { $0.fixable && !$0.fixed }.count
                if fixable > 0 && !fix {
                    print("\n\(fixable) finding sửa được — chạy `ageos doctor --fix`")
                }
            }
        } catch { CLIRuntime.fail(error) }
    }
}
