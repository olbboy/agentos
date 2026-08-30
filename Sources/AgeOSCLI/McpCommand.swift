import ArgumentParser
import AgeOSCore
import Foundation

struct McpCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Quản lý MCP servers: nguồn registry/.mcpb, enable per-client, health.",
        subcommands: [Add.self, Search.self, List.self, Enable.self, Disable.self,
                      Health.self, RestoreBackup.self]
    )

    static func makeManager(_ engine: SyncEngine) throws -> McpManager {
        let adapters = try AdapterRegistry(home: engine.home)
        return McpManager(home: engine.home, adapters: adapters,
                          warningSink: { print($0) })
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add server từ registry (tên io.github.owner/name), file .mcpb, hoặc --manual.")

        @Argument(help: "Tên registry hoặc path file .mcpb (bỏ trống khi dùng --manual).")
        var source: String?

        @Option(name: .long, help: "Tên server khai báo tay (đi kèm --command).")
        var manual: String?

        @Option(name: .long, help: "Command cho server manual (vd: npx).")
        var command: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Args cho server manual.")
        var args: [String] = []

        @Flag(name: .long, help: "Xuất JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let manager = try McpCommand.makeManager(engine)
                let model: McpServerModel
                if let manual {
                    guard let command else {
                        throw AgeOSError(.conflict, "--manual cần kèm --command",
                                         remedy: "Ví dụ: ageos mcp add --manual my-server --command npx --args -y my-pkg")
                    }
                    model = McpServerModel(id: "local/\(manual)", name: manual, description: "khai báo tay",
                                           version: "manual", source: "manual",
                                           launch: .init(transport: .stdio, command: command, args: args))
                } else if let source, source.hasSuffix(".mcpb") {
                    model = try McpbImporter.importBundle(
                        at: URL(fileURLWithPath: (source as NSString).expandingTildeInPath), home: engine.home)
                } else if let source {
                    let registry = McpRegistrySource(home: engine.home)
                    model = try await registry.get(name: source)
                } else {
                    throw AgeOSError(.conflict, "Cần tên registry, file .mcpb, hoặc --manual",
                                     remedy: "Xem `ageos mcp add --help`")
                }
                try manager.library.upsert(model)
                if json {
                    CLIRuntime.printJSON(model)
                } else {
                    print("✓ Đã add \(model.id) @ \(model.version) (\(model.launch.transport.rawValue))")
                    let required = model.envSchema.filter(\.required)
                    if !required.isEmpty {
                        print("  env bắt buộc khi enable: \(required.map(\.name).joined(separator: ", "))")
                    }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Search: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Tìm server trên registry chính thức.")

        @Argument(help: "Từ khóa.")
        var query: String

        @Flag(name: .long, help: "Xuất JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let registry = McpRegistrySource(home: engine.home)
                let results = try await registry.search(query)
                if json {
                    CLIRuntime.printJSON(results)
                } else if results.isEmpty {
                    print("Không có kết quả cho '\(query)'")
                } else {
                    for r in results {
                        let desc = r.description.count > 70 ? r.description.prefix(67) + "..." : r.description
                        print("\(r.id) @ \(r.version)\n    \(desc)")
                    }
                    print("\nAdd: ageos mcp add <tên đầy đủ>")
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Server đã add vào library.")

        @Flag(name: .long, help: "Xuất JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let servers = try McpLibrary(home: engine.home).load()
                if json {
                    CLIRuntime.printJSON(servers)
                } else if servers.isEmpty {
                    print("Library MCP trống. Add: ageos mcp add <registry-name|file.mcpb>")
                } else {
                    let lock = try Lockfile.load(from: engine.home.lockfilePath)
                    for s in servers {
                        let targets = lock.mcpServers[s.id]?.targets.keys.sorted().joined(separator: ", ") ?? "chưa enable"
                        print("\(s.id) @ \(s.version) [\(s.launch.transport.rawValue)] → \(targets)")
                    }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Enable: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Ghi entry server vào config một client (có backup).")

        @Argument(help: "Server id hoặc tên ngắn.")
        var server: String

        @Option(name: .long, help: "Adapter id (claude-code, claude-desktop, codex, grok, antigravity).")
        var target: String

        @Option(name: .long, help: "Path project (chỉ client có config project, vd claude-code .mcp.json).")
        var project: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Env dạng KEY=VALUE (lặp cho nhiều biến).")
        var env: [String] = []

        @Flag(name: .long, help: "Xuất JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let manager = try McpCommand.makeManager(engine)
                var envOverrides: [String: String] = [:]
                for pair in env {
                    guard let eq = pair.firstIndex(of: "=") else {
                        throw AgeOSError(.conflict, "--env phải dạng KEY=VALUE, nhận được '\(pair)'")
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
        static let configuration = CommandConfiguration(abstract: "Gỡ entry server khỏi config client (chỉ entry của AgeOS).")

        @Argument(help: "Server id hoặc tên ngắn.")
        var server: String

        @Option(name: .long, help: "Adapter id.")
        var target: String

        @Option(name: .long, help: "Path project nếu enable scope project.")
        var project: String?

        @Flag(name: .long, help: "Xuất JSON.")
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
                    print("✓ Đã gỡ '\(outcome.entryName)' khỏi \(outcome.configPath)")
                    if let b = outcome.backupPath { print("  backup: \(b)") }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Health: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Handshake stdio + tools/list, đo latency và schema tokens.")

        @Argument(help: "Server id hoặc tên ngắn.")
        var server: String

        @Option(name: .long, help: "Timeout giây (mặc định 15).")
        var timeout: Int = 15

        @Flag(name: .long, help: "Xuất JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let manager = try McpCommand.makeManager(engine)
                let report = try manager.health(query: server, timeout: TimeInterval(timeout))
                // Ghi kết quả vào index để Budget Meter dùng schema tokens.
                if let model = try? manager.library.find(server) {
                    try? engine.index.recordMcpHealth(entryName: model.name, report: report)
                }
                if json {
                    CLIRuntime.printJSON(report)
                } else if report.ok {
                    print("✓ \(report.serverInfo ?? server): \(report.toolCount) tools, initialize \(report.latencyMs)ms, schema ≈\(report.schemaTokens) tokens")
                } else {
                    print("✗ Health FAIL: \(report.error ?? "không rõ")")
                    if let tail = report.stderrTail, !tail.isEmpty { print("  stderr: \(tail)") }
                    Foundation.exit(1)
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct RestoreBackup: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "restore-backup",
            abstract: "Khôi phục config từ backup gần nhất.")

        @Option(name: .long, help: "Path file config cần khôi phục (vd ~/.claude.json).")
        var file: String?

        @Flag(name: .long, help: "Liệt kê backup hiện có.")
        var list = false

        @Flag(name: .long, help: "Xuất JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                if list || file == nil {
                    let records = ConfigBackup.list(home: engine.home)
                    if json {
                        CLIRuntime.printJSON(records)
                    } else if records.isEmpty {
                        print("Chưa có backup nào.")
                    } else {
                        for r in records { print("\(r.timestamp)  \(r.originalPath)") }
                        if file == nil && !list {
                            print("\nKhôi phục: ageos mcp restore-backup --file <path>")
                        }
                    }
                    return
                }
                let original = URL(fileURLWithPath: (file! as NSString).expandingTildeInPath)
                let restored = try ConfigBackup.restoreLatest(of: original, home: engine.home)
                if json {
                    CLIRuntime.printJSON(restored)
                } else {
                    print("✓ Khôi phục \(restored.originalPath) từ backup \(restored.timestamp)")
                }
            } catch { CLIRuntime.fail(error) }
        }
    }
}
