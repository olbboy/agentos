import ArgumentParser
import AgeOSCore
import Foundation

struct SourceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "source",
        abstract: "Quản lý nguồn skill (GitHub repo hoặc thư mục local).",
        subcommands: [Add.self, List.self, Sync.self, Remove.self]
    )

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Thêm nguồn và sync ngay.")

        @Argument(help: "URL GitHub (https://github.com/owner/repo) hoặc path thư mục local.")
        var location: String

        @Flag(name: .long, help: "Xuất JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let (descriptor, report) = try await engine.addSource(location)
                if json {
                    CLIRuntime.printJSON(["source": descriptor.id, "version": report.version,
                                          "installed": "\(report.installed.count)", "skipped": "\(report.skippedCount)"])
                } else {
                    print("✓ Nguồn \(descriptor.id) @ \(report.version) — \(report.installed.count) skill")
                    for detail in report.skippedDetails { print("  bỏ qua: \(detail)") }
                    if report.archived { print("  ⚠ repo đã archive — skill sẽ bị đánh dấu deprecated") }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Liệt kê nguồn đã add.")

        @Flag(name: .long, help: "Xuất JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let sources = try engine.registry.load()
                if json {
                    CLIRuntime.printJSON(sources)
                } else if sources.isEmpty {
                    print("Chưa có nguồn nào. Thêm bằng: ageos source add <github-url|path>")
                } else {
                    for s in sources {
                        let sync = s.lastSync.map { ISO8601DateFormatter().string(from: $0) } ?? "chưa sync"
                        let flags = s.archived ? " [archived]" : ""
                        print("\(s.id)\t\(s.location)\t\(sync)\(flags)")
                    }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Sync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Sync một nguồn hoặc tất cả.")

        @Argument(help: "Id nguồn (vd gh/anthropics/skills). Bỏ trống = sync tất cả.")
        var sourceId: String?

        @Flag(name: .long, help: "Xuất JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                let reports = try await engine.sync(sourceId: sourceId)
                if json {
                    CLIRuntime.printJSON(reports)
                } else if reports.isEmpty {
                    print("Không có nguồn nào để sync.")
                } else {
                    for r in reports {
                        let status = r.changed ? "\(r.installed.count) skill @ \(r.version)" : "không đổi (@ \(r.version))"
                        print("✓ \(r.sourceId): \(status)")
                        for detail in r.skippedDetails { print("  bỏ qua: \(detail)") }
                    }
                }
            } catch { CLIRuntime.fail(error) }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Gỡ nguồn khỏi registry (không xóa skill đã enable).")

        @Argument(help: "Id nguồn cần gỡ.")
        var sourceId: String

        @Flag(name: .long, help: "Xuất JSON.")
        var json = false

        func run() async throws {
            do {
                let engine = try CLIRuntime.makeEngine()
                guard let removed = try engine.registry.remove(id: sourceId) else {
                    throw AgeOSError(.notFound, "Nguồn '\(sourceId)' không tồn tại",
                                     remedy: "Xem `ageos source list`")
                }
                try engine.index.removeSource(id: sourceId)
                if json {
                    CLIRuntime.printJSON(["removed": removed.id])
                } else {
                    print("✓ Đã gỡ nguồn \(removed.id) (skill trong store giữ nguyên — dọn bằng `ageos reindex` nếu muốn)")
                }
            } catch { CLIRuntime.fail(error) }
        }
    }
}
