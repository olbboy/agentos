import Foundation

/// Client registry chính thức registry.modelcontextprotocol.io (API v0).
/// Decode "khoan dung": schema registry còn tiến hóa — field lạ bỏ qua,
/// thiếu field phụ không chết, chỉ bắt buộc name + description.
public struct McpRegistrySource: Sendable {
    public static let defaultBaseURL = "https://registry.modelcontextprotocol.io"
    let baseURL: String
    let http: HTTPClient
    let home: AgeOSHome

    public init(home: AgeOSHome, http: HTTPClient = URLSessionHTTPClient(),
                baseURL: String = McpRegistrySource.defaultBaseURL) {
        self.home = home
        self.http = http
        self.baseURL = baseURL
    }

    // MARK: - Wire types (subset khoan dung của server.json)

    struct ServerJSON: Decodable {
        var name: String
        var description: String?
        var version: String?
        var status: String?
        var packages: [Package]?
        var remotes: [Remote]?

        struct Package: Decodable {
            var registryType: String?
            var identifier: String?
            var version: String?
            var runtimeHint: String?
            var environmentVariables: [EnvVar]?

            enum CodingKeys: String, CodingKey {
                case registryType = "registry_type"
                case identifier, version
                case runtimeHint = "runtime_hint"
                case environmentVariables = "environment_variables"
            }
        }

        struct EnvVar: Decodable {
            var name: String
            var description: String?
            var isRequired: Bool?
            var isSecret: Bool?

            enum CodingKeys: String, CodingKey {
                case name, description
                case isRequired = "is_required"
                case isSecret = "is_secret"
            }
        }

        struct Remote: Decodable {
            var type: String?
            var url: String?
        }
    }

    struct ListResponse: Decodable {
        var servers: [Entry]
        /// Registry gói server.json trong `{"server": {...}}` hoặc trả phẳng — chấp nhận cả hai.
        struct Entry: Decodable {
            var server: ServerJSON

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let wrapped = try container.decodeIfPresent(ServerJSON.self, forKey: .server) {
                    server = wrapped
                } else {
                    server = try ServerJSON(from: decoder)
                }
            }

            enum CodingKeys: String, CodingKey { case server }
        }
    }

    // MARK: - API

    public func search(_ query: String, limit: Int = 20) async throws -> [McpServerModel] {
        var components = URLComponents(string: "\(baseURL)/v0/servers")!
        components.queryItems = [.init(name: "search", value: query), .init(name: "limit", value: "\(limit)")]
        let (data, response) = try await http.get(components.url!, headers: ["Accept": "application/json"])
        guard response.statusCode == 200 else {
            throw AgeOSError(.network, "Registry MCP trả \(response.statusCode) khi search '\(query)'",
                             remedy: "Thử lại sau; registry.modelcontextprotocol.io có thể đang bảo trì")
        }
        try? cache(data: data, key: "search-\(query)")
        let decoded = try Self.decodeList(data)
        return decoded.compactMap { Self.model(from: $0) }
    }

    public func get(name: String) async throws -> McpServerModel {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let url = URL(string: "\(baseURL)/v0/servers/\(encoded)")!
        let (data, response) = try await http.get(url, headers: ["Accept": "application/json"])
        switch response.statusCode {
        case 200:
            try? cache(data: data, key: "server-\(name)")
            // Endpoint chi tiết có thể trả object đơn hoặc versioned list — thử cả hai.
            if let single = try? JSONDecoder().decode(ListResponse.Entry.self, from: data),
               let model = Self.model(from: single.server) {
                return model
            }
            if let list = try? Self.decodeList(data), let first = list.first, let model = Self.model(from: first) {
                return model
            }
            throw AgeOSError(.unsupported, "Không hiểu payload registry cho '\(name)' (schema đổi?)",
                             remedy: "Cập nhật AgeOS hoặc add tay: `ageos mcp add --manual ...`")
        case 404:
            throw AgeOSError(.notFound, "Registry không có server '\(name)'",
                             remedy: "Tìm bằng `ageos mcp search <từ khóa>` để lấy đúng tên namespace")
        default:
            throw AgeOSError(.network, "Registry MCP trả \(response.statusCode) cho '\(name)'")
        }
    }

    static func decodeList(_ data: Data) throws -> [ServerJSON] {
        do {
            return try JSONDecoder().decode(ListResponse.self, from: data).servers.map(\.server)
        } catch {
            throw AgeOSError(.unsupported, "Không parse được danh sách registry: \(error)",
                             remedy: "Schema registry có thể đã đổi — cập nhật AgeOS")
        }
    }

    /// server.json → model chạy được. Ưu tiên: npm → pypi → remote. Trả nil nếu không dựng nổi launch.
    static func model(from json: ServerJSON) -> McpServerModel? {
        let shortName = json.name.split(separator: "/").last.map(String.init) ?? json.name
        let envSchema = (json.packages?.first?.environmentVariables ?? []).map {
            McpServerModel.EnvVar(name: $0.name, description: $0.description,
                                  required: $0.isRequired ?? false, secret: $0.isSecret ?? false)
        }

        var launch: McpServerModel.Launch?
        if let packages = json.packages {
            for pkg in packages {
                guard let identifier = pkg.identifier else { continue }
                let versionSuffix = pkg.version.map { "@\($0)" } ?? ""
                switch pkg.registryType {
                case "npm":
                    launch = .init(transport: .stdio, command: "npx", args: ["-y", identifier + versionSuffix])
                case "pypi":
                    let pin = pkg.version.map { "==\($0)" } ?? ""
                    launch = .init(transport: .stdio, command: "uvx", args: [identifier + pin])
                default:
                    continue
                }
                if launch != nil { break }
            }
        }
        if launch == nil, let remote = json.remotes?.first, let url = remote.url {
            launch = .init(transport: .http, url: url)
        }
        guard let resolved = launch else { return nil }

        return McpServerModel(id: json.name, name: shortName,
                              description: json.description ?? "",
                              version: json.version ?? "latest",
                              source: "registry.modelcontextprotocol.io",
                              launch: resolved, envSchema: envSchema)
    }

    func cache(data: Data, key: String) throws {
        let dir = home.cacheDir.appendingPathComponent("mcp-registry", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = key.replacingOccurrences(of: "[^a-zA-Z0-9.-]", with: "_", options: .regularExpression)
        try data.write(to: dir.appendingPathComponent("\(safe).json"))
    }
}
