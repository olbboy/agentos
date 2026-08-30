import Foundation

/// Import bundle `.mcpb` (ZIP + manifest.json) vào `library/mcp/<ns>/<name>/<version>/`.
/// Payload nằm yên trong library — config client trỏ vào đó, không rải file khắp máy.
public enum McpbImporter {
    struct Manifest: Decodable {
        var name: String
        var version: String?
        var description: String?
        var server: ServerBlock?

        struct ServerBlock: Decodable {
            var type: String?
            var entryPoint: String?
            var mcpConfig: McpConfig?

            enum CodingKeys: String, CodingKey {
                case type
                case entryPoint = "entry_point"
                case mcpConfig = "mcp_config"
            }
        }

        struct McpConfig: Decodable {
            var command: String?
            var args: [String]?
            var env: [String: String]?
        }
    }

    public static func importBundle(at file: URL, home: AgeOSHome) throws -> McpServerModel {
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw AgeOSError(.notFound, "File không tồn tại: \(file.path)")
        }
        let staging = home.cacheDir.appendingPathComponent("mcpb-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try unzip(file, to: staging)

        let manifestURL = staging.appendingPathComponent("manifest.json")
        guard let data = FileManager.default.contents(atPath: manifestURL.path) else {
            throw AgeOSError(.invalidSource, "Bundle thiếu manifest.json: \(file.lastPathComponent)",
                             remedy: "File .mcpb hợp lệ phải có manifest.json ở gốc")
        }
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            throw AgeOSError(.invalidSource, "manifest.json hỏng trong \(file.lastPathComponent): \(error)")
        }

        let name = manifest.name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
        let version = manifest.version ?? "0.0.0"
        let destDir = home.mcpLibraryDir
            .appendingPathComponent("local", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
        if FileManager.default.fileExists(atPath: destDir.path) {
            try FileManager.default.removeItem(at: destDir)
        }
        try AtomicFile.moveDirectory(staging, to: destDir)

        // Dựng launch từ mcp_config; placeholder ${__dirname} → thư mục bundle trong library.
        let config = manifest.server?.mcpConfig
        let dirToken = "${__dirname}"
        func resolve(_ s: String) -> String {
            s.replacingOccurrences(of: dirToken, with: destDir.path)
        }
        let command = (config?.command).map(resolve)
        let args = (config?.args ?? []).map(resolve)
        var env: [String: String] = [:]
        for (k, v) in config?.env ?? [:] { env[k] = resolve(v) }

        guard let command, !command.isEmpty else {
            throw AgeOSError(.unsupported, "Bundle \(manifest.name) không khai báo server.mcp_config.command",
                             remedy: "AgeOS MVP chỉ chạy .mcpb có mcp_config tường minh")
        }

        return McpServerModel(
            id: "local/\(name)", name: name,
            description: manifest.description ?? "",
            version: version, source: "mcpb:\(file.lastPathComponent)",
            launch: .init(transport: .stdio, command: command, args: args, env: env),
            envSchema: []
        )
    }

    static func unzip(_ file: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", file.path, destination.path]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AgeOSError(.processFailed, "Giải nén .mcpb thất bại: \(msg.prefix(200))",
                             remedy: "Kiểm tra file có phải ZIP hợp lệ (đuôi .mcpb)")
        }
    }
}
