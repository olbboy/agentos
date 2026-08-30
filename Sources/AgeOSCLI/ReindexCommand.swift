import ArgumentParser
import AgeOSCore
import Foundation

struct ReindexCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reindex",
        abstract: "Rebuild index.sqlite từ filesystem (store + sources.json)."
    )

    @Flag(name: .long, help: "Xuất JSON.")
    var json = false

    func run() async throws {
        do {
            let engine = try CLIRuntime.makeEngine()
            try engine.index.rebuild(home: engine.home, store: engine.store, registry: engine.registry)
            let count = try engine.index.listSkills().count
            if json {
                CLIRuntime.printJSON(["skills": count])
            } else {
                print("✓ Reindex xong — \(count) skill trong index")
            }
        } catch { CLIRuntime.fail(error) }
    }
}
