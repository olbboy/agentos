import Foundation

/// Một MCP server trong library — hợp nhất từ registry server.json, manifest .mcpb,
/// hoặc khai báo tay. `launch` là thứ cuối cùng được ghi vào config client.
public struct McpServerModel: Sendable, Codable, Equatable {
    /// Id namespace: registry `io.github.owner/name`, mcpb/manual `local/<name>`.
    public var id: String
    /// Tên entry trong config client (ngắn, không slash).
    public var name: String
    public var description: String
    public var version: String
    public var source: String
    public var launch: Launch
    /// Schema env từ nguồn — enable dùng để hỏi giá trị còn thiếu.
    public var envSchema: [EnvVar]

    public struct Launch: Sendable, Codable, Equatable {
        public enum Transport: String, Sendable, Codable { case stdio, http }
        public var transport: Transport
        /// stdio
        public var command: String?
        public var args: [String]
        /// http/sse
        public var url: String?
        /// Giá trị env đã điền (plaintext ở MVP — Keychain là v1.1).
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

    /// Env bắt buộc còn thiếu giá trị.
    public func missingRequiredEnv() -> [EnvVar] {
        envSchema.filter { $0.required && launch.env[$0.name] == nil }
    }

    public var sensitiveEnvKeys: [String] {
        envSchema.filter(\.secret).map(\.name).sorted()
    }
}

/// Kho model MCP đã add — persist `mcp-servers.json` trong home (nguồn chân lý file).
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
            throw AgeOSError(.configUnreadable, "mcp-servers.json hỏng: \(error)",
                             remedy: "Sửa tay \(path.path) hoặc xóa rồi add lại server")
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
            throw AgeOSError(.notFound, "MCP server '\(query)' chưa có trong library",
                             remedy: "Add trước: `ageos mcp add <registry-name|file.mcpb>` hoặc xem `ageos mcp list`")
        default:
            throw AgeOSError(.conflict, "'\(query)' khớp nhiều server: \(matches.map(\.id).joined(separator: ", "))",
                             remedy: "Dùng id đầy đủ")
        }
    }
}
