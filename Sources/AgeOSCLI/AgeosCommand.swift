import ArgumentParser
import AgeOSCore
import Foundation

@main
struct AgeosCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ageos",
        abstract: "Manage and distribute Agent Skills and MCP servers from one central library.",
        version: "0.1.0",
        subcommands: [SourceCommand.self, ListCommand.self, ReindexCommand.self,
                      EnableCommand.self, DisableCommand.self, TargetsCommand.self, DoctorCommand.self,
                      McpCommand.self,
                      AdoptCommand.self, ScanCommand.self, BudgetCommand.self, LintCommand.self,
                      SearchCommand.self]
    )
}

/// Consistent exit codes: 0 ok · 1 runtime error · 64 usage (ArgumentParser handles usage itself).
enum CLIRuntime {
    static func makeEngine() throws -> SyncEngine {
        try SyncEngine(home: AgeOSHome())
    }

    /// "1 skill" / "2 skills" — English inflects for number, Vietnamese does not.
    ///
    /// The Vietnamese original wrote "\(n) skill" for every n and was correct. Translating to
    /// English is what exposed the problem, so fixing it belongs to finishing the translation,
    /// not to adding a feature. Gathered here so ten call sites do not each do it differently.
    static func count(_ n: Int, _ singular: String, plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// Prints the error to stderr and exits with code 1.
    static func fail(_ error: Error) -> Never {
        let text: String
        if let e = error as? AgeOSError {
            text = e.description
        } else {
            text = "\(error)"
        }
        FileHandle.standardError.write(Data(("ageos: " + text + "\n").utf8))
        Foundation.exit(1)
    }

    static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    }
}
