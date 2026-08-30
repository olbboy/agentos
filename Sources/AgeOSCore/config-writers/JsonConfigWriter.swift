import Foundation

/// Ghi config JSON (claude-code `~/.claude.json`, claude-desktop, antigravity).
/// JSONSerialization giữ mọi key lạ; output sortedKeys (order chuẩn hóa —
/// các file này vốn do máy ghi, không ai giữ order tay).
public struct JsonConfigWriter: ConfigWriter {
    public init() {}

    public func upsertEntry(name: String, launch: McpServerModel.Launch, keyPath: String, in file: URL) throws {
        var root = try loadRoot(file)
        var servers = (root[keyPath] as? [String: Any]) ?? [:]
        servers[name] = Self.entryValue(for: launch)
        root[keyPath] = servers
        try write(root, to: file)
    }

    public func removeEntry(name: String, keyPath: String, in file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        var root = try loadRoot(file)
        guard var servers = root[keyPath] as? [String: Any], servers[name] != nil else { return }
        servers.removeValue(forKey: name)
        root[keyPath] = servers
        try write(root, to: file)
    }

    public func hasEntry(name: String, keyPath: String, in file: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let root = try loadRoot(file)
        return (root[keyPath] as? [String: Any])?[name] != nil
    }

    /// Đọc entry hiện có (để so sánh/hiển thị).
    public func readEntry(name: String, keyPath: String, in file: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let root = try loadRoot(file)
        return (root[keyPath] as? [String: Any])?[name] as? [String: Any]
    }

    static func entryValue(for launch: McpServerModel.Launch) -> [String: Any] {
        switch launch.transport {
        case .stdio:
            var entry: [String: Any] = ["command": launch.command ?? ""]
            if !launch.args.isEmpty { entry["args"] = launch.args }
            if !launch.env.isEmpty { entry["env"] = launch.env }
            return entry
        case .http:
            return ["type": "http", "url": launch.url ?? ""]
        }
    }

    func loadRoot(_ file: URL) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: file.path) else {
            return [:] // file chưa tồn tại → bắt đầu rỗng (sẽ tạo mới)
        }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch let error as NSError {
            // Chỉ chỗ lỗi để user tự sửa — TUYỆT ĐỐI không ghi đè file hỏng.
            let detail = (error.userInfo["NSDebugDescription"] as? String) ?? error.localizedDescription
            throw AgeOSError(.configUnreadable, "Config JSON is already malformed at \(file.path): \(detail)",
                             remedy: "Fix the file by hand (check commas and braces), then run again — AgeOS never overwrites a malformed file")
        }
        guard let dict = parsed as? [String: Any] else {
            throw AgeOSError(.configUnreadable, "Config \(file.path) is not a JSON object at the root",
                             remedy: "The file must be shaped { ... } — check its contents")
        }
        return dict
    }

    func write(_ root: [String: Any], to file: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try AtomicFile.write(data, to: file)
    }
}
