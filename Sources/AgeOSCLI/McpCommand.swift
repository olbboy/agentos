import ArgumentParser
import AgeOSCore
import Foundation

struct McpCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Manage MCP servers: registry and .mcpb sources, per-client enable, health.",
        subcommands: [Add.self, Search.self, List.self, Enable.self, Disable.self,
                      Remove.self, Health.self, RestoreBackup.self]
    )

    static func makeManager(_ engine: SyncEngine) throws -> McpManager {
        let adapters = try AdapterRegistry(home: engine.home)
        return McpManager(home: engine.home, adapters: adapters,
                          warningSink: { print($0) })
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a server from the registry (io.github.owner/name), a .mcpb file, or --manual.")

        @Argument(help: "Registry name, or path to a .mcpb file (leave empty when using --manual).")
        var source: String?

        @Option(name: .long, help: "Name for a hand-declared server (pair it with --command).")
        var manual: String?

        @Option(name: .long, help: "Command for a manual server (e.g. npx).")
        var command: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Args for a manual server.")
        var args: [String] = []

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let manager = try McpCommand.makeManager(engine)
                let model: McpServerModel
                if let manual {
                    guard let command else {
                        throw AgeOSError(.conflict, "--manual needs --command alongside it",
                                         remedy: "For example: ageos mcp add --manual my-server --command npx --args -y my-pkg")
                    }
                    model = McpServerModel(id: "local/\(manual)", name: manual, description: "declared by hand",
                                           version: "manual", source: "manual",
                                           launch: .init(transport: .stdio, command: command, args: args))
                } else if let source, source.hasSuffix(".mcpb") {
                    model = try McpbImporter.importBundle(
                        at: URL(fileURLWithPath: (source as NSString).expandingTildeInPath), home: engine.home)
                } else if let source {
                    let registry = McpRegistrySource(home: engine.home)
                    model = try await registry.get(name: source)
                } else {
                    throw AgeOSError(.conflict, "Need a registry name, a .mcpb file, or --manual",
                                     remedy: "See `ageos mcp add --help`")
                }
                try manager.library.upsert(model)
                if json {
                    CLIRuntime.printJSON(model)
                } else {
                    print("✓ Added \(model.id) @ \(model.version) (\(model.launch.transport.rawValue))")
                    let required = model.envSchema.filter(\.required)
                    if !required.isEmpty {
                        print("  env required when enabling: \(required.map(\.name).joined(separator: ", "))")
                    }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Search: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Search the official registry for a server.")

        @Argument(help: "Keyword.")
        var query: String

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let registry = McpRegistrySource(home: engine.home)
                let results = try await registry.search(query)
                if json {
                    CLIRuntime.printJSON(results)
                } else if results.isEmpty {
                    print("No results for '\(query)'")
                } else {
                    for r in results {
                        let desc = r.description.count > 70 ? r.description.prefix(67) + "..." : r.description
                        print("\(r.id) @ \(r.version)\n    \(desc)")
                    }
                    print("\nAdd one: ageos mcp add <full-name>")
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Servers already added to the library.")

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let servers = try McpLibrary(home: engine.home).load()
                if json {
                    CLIRuntime.printJSON(servers)
                } else if servers.isEmpty {
                    print("The MCP library is empty. Add one: ageos mcp add <registry-name|file.mcpb>")
                } else {
                    let lock = try Lockfile.load(from: engine.home.lockfilePath)
                    for s in servers {
                        let targets = lock.mcpServers[s.id]?.targets.keys.sorted().joined(separator: ", ") ?? "not enabled"
                        print("\(s.id) @ \(s.version) [\(s.launch.transport.rawValue)] → \(targets)")
                    }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Enable: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Write the server entry into one client config (with a backup).")

        @Argument(help: "Server id, or the short name.")
        var server: String

        @Option(name: .long, help: "Adapter id (claude-code, claude-desktop, codex, grok, antigravity).")
        var target: String

        @Option(name: .long, help: "Project path (only for clients with a project config, e.g. claude-code .mcp.json).")
        var project: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Env as KEY=VALUE (repeat for several variables).")
        var env: [String] = []

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let manager = try McpCommand.makeManager(engine)
                var envOverrides: [String: String] = [:]
                for pair in env {
                    guard let eq = pair.firstIndex(of: "=") else {
                        throw AgeOSError(.conflict, "--env must be KEY=VALUE, got '\(pair)'")
                    }
                    envOverrides[String(pair[..<eq])] = String(pair[pair.index(after: eq)...])
                }
                let projectURL = project.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
                let outcome = try manager.enable(query: server, adapterId: target,
                                                 project: projectURL, envOverrides: envOverrides)
                if json {
                    CLIRuntime.printJSON(outcome)
                } else {
                    print("✓ \(outcome.serverId) → \(outcome.adapterId) [\(outcome.scope)] entry '\(outcome.entryName)'")
                    print("  config: \(outcome.configPath)")
                    if let b = outcome.backupPath { print("  backup: \(b)") }
                    if let n = outcome.note { print("  ⚠ \(n)") }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Disable: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove the server entry from a client config (only AgeOS entries).")

        @Argument(help: "Server id, or the short name.")
        var server: String

        @Option(name: .long, help: "Adapter id.")
        var target: String

        @Option(name: .long, help: "Project path, if it was enabled at project scope.")
        var project: String?

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let manager = try McpCommand.makeManager(engine)
                let projectURL = project.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
                let outcome = try manager.disable(query: server, adapterId: target, project: projectURL)
                if json {
                    CLIRuntime.printJSON(outcome)
                } else {
                    print("✓ Removed '\(outcome.entryName)' from \(outcome.configPath)")
                    if let b = outcome.backupPath { print("  backup: \(b)") }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a server from the library (disable it on every client first).")

        @Argument(help: "Server id, or the short name.")
        var server: String

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let manager = try McpCommand.makeManager(engine)
                let removed = try manager.removeFromLibrary(query: server)
                if json {
                    CLIRuntime.printJSON(["removed": removed.id])
                } else {
                    print("✓ Removed \(removed.id) from the library (any payload under library/mcp is kept — GC comes in a later version)")
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Health: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "stdio handshake plus tools/list; measures latency and schema tokens.")

        @Argument(help: "Server id, or the short name.")
        var server: String

        @Option(name: .long, help: "Timeout in seconds (default 15).")
        var timeout: Int = 15

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let manager = try McpCommand.makeManager(engine)
                let report = try manager.health(query: server, timeout: TimeInterval(timeout))
                // Record the result in the index so the Budget Meter can use the schema tokens.
                if let model = try? manager.library.find(server) {
                    try? engine.index.recordMcpHealth(entryName: model.name, report: report)
                }
                if json {
                    CLIRuntime.printJSON(report)
                } else if report.ok {
                    print("✓ \(report.serverInfo ?? server): \(report.toolCount) tools, initialize \(report.latencyMs)ms, schema ≈\(report.schemaTokens) tokens")
                } else {
                    print("✗ Health FAILED: \(report.error ?? "unknown")")
                    if let tail = report.stderrTail, !tail.isEmpty { print("  stderr: \(tail)") }
                    Foundation.exit(1)
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct RestoreBackup: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "restore-backup",
            abstract: "Restore a config from the most recent backup.")

        @Option(name: .long, help: "Path of the config file to restore (e.g. ~/.claude.json).")
        var file: String?

        @Flag(name: .long, help: "List the backups that exist.")
        var list = false

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                if list || file == nil {
                    let records = ConfigBackup.list(home: engine.home)
                    if json {
                        CLIRuntime.printJSON(records)
                    } else if records.isEmpty {
                        print("No backups yet.")
                    } else {
                        for r in records { print("\(r.timestamp)  \(r.originalPath)") }
                        if file == nil && !list {
                            print("\nRestore one: ageos mcp restore-backup --file <path>")
                        }
                    }
                    return
                }
                let original = URL(fileURLWithPath: (file! as NSString).expandingTildeInPath)
                let restored = try ConfigBackup.restoreLatest(of: original, home: engine.home)
                if json {
                    CLIRuntime.printJSON(restored)
                } else {
                    print("✓ Restored \(restored.originalPath) from the \(restored.timestamp) backup")
                }
            } catch { CLIRuntime.fail(error) }
        }
    }
}
