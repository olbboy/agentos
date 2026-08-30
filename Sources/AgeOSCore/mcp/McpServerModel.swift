import Foundation

/// One MCP server in the library — unified from a registry server.json, a .mcpb manifest,
/// or a manual declaration. `launch` is what finally gets written into the client config.
public struct McpServerModel: Sendable, Codable, Equatable {
    /// Id namespace: registry `io.github.owner/name`, mcpb/manual `local/<name>`.
    public var id: String
    /// The entry name in the client config (short, no slashes).
    public var name: String
    public var description: String
    public var version: String
    public var source: String
    public var launch: Launch
    /// The env schema from the source — enable uses it to ask for missing values.
    public var envSchema: [EnvVar]

    public struct Launch: Sendable, Codable, Equatable {
        public enum Transport: String, Sendable, Codable { case stdio, http }
        public var transport: Transport
        /// stdio
        public var command: String?
        public var args: [String]
        /// http/sse
        public var url: String?
        /// The env values that were filled in (plaintext at MVP — Keychain is v1.1).
        public var env: [String: String]

        public init(transport: Transport, command: String? = nil, args: [String] = [],
                    url: String? = nil, env: [String: String] = [:]) {
            self.transport = transport
            self.command = command
            self.args = args
            self.url = url
            self.env = env
        }
    }

    public struct EnvVar: Sendable, Codable, Equatable {
        public var name: String
        public var description: String?
        public var required: Bool
        public var secret: Bool

        public init(name: String, description: String? = nil, required: Bool = false, secret: Bool = false) {
            self.name = name
            self.description = description
            self.required = required
            self.secret = secret
        }
    }

    public init(id: String, name: String, description: String, version: String,
                source: String, launch: Launch, envSchema: [EnvVar] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.source = source
        self.launch = launch
        self.envSchema = envSchema
    }

    /// Required env that is still missing a value.
    public func missingRequiredEnv() -> [EnvVar] {
        envSchema.filter { $0.required && launch.env[$0.name] == nil }
    }

    public var sensitiveEnvKeys: [String] {
        envSchema.filter(\.secret).map(\.name).sorted()
    }
}

/// The store of added MCP models — persisted to `mcp-servers.json` in the home (the file is the truth).
public struct McpLibrary: Sendable {
    public let home: AgeOSHome
    var path: URL { home.root.appendingPathComponent("mcp-servers.json") }

    public init(home: AgeOSHome) {
        self.home = home
    }

    public func load() throws -> [McpServerModel] {
        guard let data = FileManager.default.contents(atPath: path.path) else { return [] }
        do {
            return try JSONDecoder().decode([McpServerModel].self, from: data)
        } catch {
            throw AgeOSError(.configUnreadable, "mcp-servers.json is malformed: \(error)",
                             remedy: "Fix \(path.path) by hand, or delete it and add the servers again")
        }
    }

    public func save(_ servers: [McpServerModel]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(try encoder.encode(servers.sorted { $0.id < $1.id }), to: path)
    }

    @discardableResult
    public func upsert(_ server: McpServerModel) throws -> McpServerModel {
        var all = try load()
        if let i = all.firstIndex(where: { $0.id == server.id }) {
            all[i] = server
        } else {
            all.append(server)
        }
        try save(all)
        return server
    }

    public func find(_ query: String) throws -> McpServerModel {
        let all = try load()
        if let exact = all.first(where: { $0.id == query }) { return exact }
        let matches = all.filter { $0.name == query }
        switch matches.count {
        case 1: return matches[0]
        case 0:
            throw AgeOSError(.notFound, "MCP server '\(query)' is not in the library yet",
                             remedy: "Add it first with `ageos mcp add <registry-name|file.mcpb>`, or see `ageos mcp list`")
        default:
            throw AgeOSError(.conflict, "'\(query)' matches several servers: \(matches.map(\.id).joined(separator: ", "))",
                             remedy: "Use the full id")
        }
    }
}
