import Foundation
import TOMLKit

/// Ghi config TOML (codex + grok `config.toml`, key `[mcp_servers.<name>]`).
/// TOMLKit round-trip GIỮ giá trị + key lạ nhưng normalize format và CÓ THỂ MẤT
/// COMMENT của user — hạn chế đã chốt ở validate (Session 1): chấp nhận + cảnh báo,
/// backup luôn có trước khi ghi. Line-targeted editor là hướng replan nếu cộng đồng phản ứng.
public struct TomlConfigWriter: ConfigWriter {
    public init() {}

    /// Writer trả cảnh báo qua callback để CLI in (protocol không có kênh warning).
    public var onWarning: (@Sendable (String) -> Void)?

    public func upsertEntry(name: String, launch: McpServerModel.Launch, keyPath: String, in file: URL) throws {
        let table = try loadTable(file)
        warnIfHasComments(file)
        let servers = (table[keyPath]?.table) ?? TOMLTable()
        let entry = TOMLTable()
        switch launch.transport {
        case .stdio:
            entry["command"] = launch.command ?? ""
            if !launch.args.isEmpty {
                let arr = TOMLArray()
                for a in launch.args { arr.append(a) }
                entry["args"] = arr
            }
            if !launch.env.isEmpty {
                let envTable = TOMLTable()
                for (k, v) in launch.env.sorted(by: { $0.key < $1.key }) { envTable[k] = v }
                entry["env"] = envTable
            }
        case .http:
            entry["url"] = launch.url ?? ""
        }
        servers[name] = entry
        table[keyPath] = servers
        try write(table, to: file)
    }

    public func removeEntry(name: String, keyPath: String, in file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let table = try loadTable(file)
        guard let servers = table[keyPath]?.table, servers.contains(key: name) else { return }
        servers.remove(at: name)
        table[keyPath] = servers
        try write(table, to: file)
    }

    public func hasEntry(name: String, keyPath: String, in file: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let table = try loadTable(file)
        return table[keyPath]?.table?.contains(key: name) ?? false
    }

    func loadTable(_ file: URL) throws -> TOMLTable {
        guard let data = FileManager.default.contents(atPath: file.path),
              let text = String(data: data, encoding: .utf8) else {
            return TOMLTable()
        }
        do {
            return try TOMLTable(string: text)
        } catch {
            throw AgeOSError(.configUnreadable, "Config TOML is already malformed at \(file.path): \(error)",
                             remedy: "Fix the file by hand, then run again — AgeOS never overwrites a malformed file")
        }
    }

    func warnIfHasComments(_ file: URL) {
        guard let data = FileManager.default.contents(atPath: file.path),
              let text = String(data: data, encoding: .utf8),
              text.contains("#") else { return }
        onWarning?("""
        ⚠ \(file.lastPathComponent) contains comments (#) — TOML is normalized on write and \
        comments may be lost. A full backup is kept in ~/.ageos/backups/ (restore with `ageos mcp restore-backup`).
        """)
    }

    func write(_ table: TOMLTable, to file: URL) throws {
        try AtomicFile.write(Data(table.convert(to: .toml).utf8), to: file)
    }
}
