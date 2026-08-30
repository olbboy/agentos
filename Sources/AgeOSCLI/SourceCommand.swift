import ArgumentParser
import AgeOSCore
import Foundation

struct SourceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "source",
        abstract: "Manage skill sources (a GitHub repo, or a local folder).",
        subcommands: [Add.self, List.self, Sync.self, Remove.self]
    )

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a source and sync it right away.")

        @Argument(help: "GitHub URL (https://github.com/owner/repo), or a local folder path.")
        var location: String

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let (descriptor, report) = try await engine.addSource(location)
                if json {
                    CLIRuntime.printJSON(["source": descriptor.id, "version": report.version,
                                          "installed": "\(report.installed.count)", "skipped": "\(report.skippedCount)"])
                } else {
                    print("✓ Source \(descriptor.id) @ \(report.version) — \(CLIRuntime.count(report.installed.count, "skill"))")
                    for detail in report.skippedDetails { print("  skipped: \(detail)") }
                    if report.archived { print("  ⚠ the repo is archived — its skills will be marked deprecated") }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the sources you have added.")

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let sources = try engine.registry.load()
                if json {
                    CLIRuntime.printJSON(sources)
                } else if sources.isEmpty {
                    print("No sources yet. Add one with: ageos source add <github-url|path>")
                } else {
                    for s in sources {
                        let sync = s.lastSync.map { ISO8601DateFormatter().string(from: $0) } ?? "never synced"
                        let flags = s.archived ? " [archived]" : ""
                        print("\(s.id)\t\(s.location)\t\(sync)\(flags)")
                    }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Sync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Sync one source, or all of them.")

        @Argument(help: "Source id (for example gh/anthropics/skills). Leave empty to sync all.")
        var sourceId: String?

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let reports = try await engine.sync(sourceId: sourceId)
                if json {
                    CLIRuntime.printJSON(reports)
                } else if reports.isEmpty {
                    print("No sources to sync.")
                } else {
                    for r in reports {
                        let status = r.changed ? "\(CLIRuntime.count(r.installed.count, "skill")) @ \(r.version)" : "unchanged (@ \(r.version))"
                        print("✓ \(r.sourceId): \(status)")
                        for detail in r.skippedDetails { print("  skipped: \(detail)") }
                    }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a source from the registry (enabled skills stay).")

        @Argument(help: "Id of the source to remove.")
        var sourceId: String

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                guard let removed = try engine.registry.remove(id: sourceId) else {
                    throw AgeOSError(.notFound, "Source '\(sourceId)' does not exist",
                                     remedy: "See `ageos source list`")
                }
                try engine.index.removeSource(id: sourceId)
                if json {
                    CLIRuntime.printJSON(["removed": removed.id])
                } else {
                    print("✓ Removed source \(removed.id) (skills in the store are untouched — clean them with `ageos reindex` if you want)")
                }
            } catch { CLIRuntime.fail(error) }
        }
    }
}
