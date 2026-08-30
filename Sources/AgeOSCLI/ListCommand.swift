import ArgumentParser
import AgeOSCore
import Foundation

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Liệt kê skill trong library."
    )

    @Flag(name: .long, help: "Xuất JSON.")
    var json = false

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            let skills = try engine.index.listSkills()
            if json {
                CLIRuntime.printJSON(skills.map {
                    ["id": $0.id, "description": $0.description, "version": $0.version,
                     "deprecated": $0.deprecated ? "true" : "false"]
                })
            } else if skills.isEmpty {
                print("Library trống. Bắt đầu: ageos source add https://github.com/anthropics/skills")
            } else {
                for s in skills {
                    let flag = s.deprecated ? " [deprecated]" : ""
                    let desc = s.description.count > 80 ? s.description.prefix(77) + "..." : s.description
                    print("\(s.id) @ \(s.version)\(flag)\n    \(desc)")
                }
                print("\n\(skills.count) skill")
            }
        } catch { CLIRuntime.fail(error) }
    }
}
