import Foundation

/// Imports a `.mcpb` bundle (a ZIP plus manifest.json) into `library/mcp/<ns>/<name>/<version>/`.
/// The payload stays put inside the library — the client config points at it, rather than scattering files across the machine.
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
            throw AgeOSError(.notFound, "File does not exist: \(file.path)")
        }
        let staging = home.cacheDir.appendingPathComponent("mcpb-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try unzip(file, to: staging)

        let manifestURL = staging.appendingPathComponent("manifest.json")
        guard let data = FileManager.default.contents(atPath: manifestURL.path) else {
            throw AgeOSError(.invalidSource, "Bundle is missing manifest.json: \(file.lastPathComponent)",
                             remedy: "A valid .mcpb file must contain manifest.json at its root")
        }
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            throw AgeOSError(.invalidSource, "manifest.json is malformed in \(file.lastPathComponent): \(error)")
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

        // Build launch from mcp_config; the ${__dirname} placeholder resolves to the bundle directory in the library.
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
            throw AgeOSError(.unsupported, "Bundle \(manifest.name) does not declare server.mcp_config.command",
                             remedy: "The AgeOS MVP only runs .mcpb bundles with an explicit mcp_config")
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
            throw AgeOSError(.processFailed, "Unpacking the .mcpb failed: \(msg.prefix(200))",
                             remedy: "Check that the file is a valid ZIP (.mcpb extension)")
        }
    }
}
