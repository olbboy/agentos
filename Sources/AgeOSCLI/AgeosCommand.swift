import ArgumentParser
import AgeOSCore
import Foundation

@main
struct AgeosCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ageos",
        abstract: "Quản lý & phân phối Agent Skills + MCP servers từ một library trung tâm.",
        version: "0.1.0",
        subcommands: [SourceCommand.self, ListCommand.self, ReindexCommand.self,
                      EnableCommand.self, DisableCommand.self, TargetsCommand.self, DoctorCommand.self,
                      McpCommand.self,
                      AdoptCommand.self, ScanCommand.self, BudgetCommand.self, LintCommand.self,
                      SearchCommand.self]
    )
}

/// Exit codes nhất quán: 0 ok · 1 lỗi runtime · 64 usage (ArgumentParser tự xử lý usage).
enum CLIRuntime {
    static func makeEngine() throws -> SyncEngine {
        try SyncEngine(home: AgeOSHome())
    }

    /// In lỗi chuẩn stderr rồi thoát mã 1.
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
