import Foundation
import MCP
import AgeOSCore

/// `ageos-mcp` — an MCP stdio server that lets an AGENT manage skills and MCP servers through AgeOS core.
/// The tool descriptions are deliberately SHORT: this server is measured by the Budget Meter
/// too, and it should set an example on catalog cost.
@main
struct AgeosMcpMain {
    static func main() async throws {
        let server = Server(
            name: "ageos",
            version: "0.1.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: AgeosTools.definitions)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let text = try await AgeosTools.dispatch(name: params.name,
                                                         arguments: params.arguments ?? [:])
                return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
            } catch let error as AgeOSError {
                return CallTool.Result(content: [.text(text: "ERROR [\(error.code.rawValue)]: \(error.description)",
                                                       annotations: nil, _meta: nil)],
                                       isError: true)
            } catch {
                return CallTool.Result(content: [.text(text: "ERROR: \(error)", annotations: nil, _meta: nil)],
                                       isError: true)
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

enum AgeosTools {
    static let definitions: [Tool] = [
        Tool(name: "search_skills",
             description: "Search skills in AgeOS library and skills.sh index.",
             inputSchema: ["type": "object",
                           "properties": ["query": ["type": "string"]],
                           "required": ["query"]]),
        Tool(name: "skill_info",
             description: "Details, quality score and lint for one skill.",
             inputSchema: ["type": "object",
                           "properties": ["skill": ["type": "string", "description": "id or short name"]],
                           "required": ["skill"]]),
        Tool(name: "install_skill",
             description: "Add a GitHub repo (owner/repo) or local path as source and sync its skills.",
             inputSchema: ["type": "object",
                           "properties": ["source": ["type": "string"]],
                           "required": ["source"]]),
        Tool(name: "enable_skill",
             description: "Enable a library skill for an agent (symlink/copy per adapter).",
             inputSchema: ["type": "object",
                           "properties": ["skill": ["type": "string"],
                                          "target": ["type": "string"],
                                          "project": ["type": "string", "description": "optional project dir"]],
                           "required": ["skill", "target"]]),
        Tool(name: "disable_skill",
             description: "Remove an AgeOS-managed skill from an agent.",
             inputSchema: ["type": "object",
                           "properties": ["skill": ["type": "string"],
                                          "target": ["type": "string"],
                                          "project": ["type": "string"]],
                           "required": ["skill", "target"]]),
        Tool(name: "list_targets",
             description: "List agent adapters and detection state on this machine.",
             inputSchema: ["type": "object", "properties": [:]]),
        Tool(name: "scan_library",
             description: "Scan all loaded skills: exact/near dupes, deprecated, description lint.",
             inputSchema: ["type": "object", "properties": [:]]),
        Tool(name: "budget_report",
             description: "Estimate always-loaded context tokens per agent (±20%).",
             inputSchema: ["type": "object",
                           "properties": ["target": ["type": "string", "description": "optional adapter id"]]]),
        Tool(name: "doctor",
             description: "Check lockfile vs filesystem drift; fix=true repairs.",
             inputSchema: ["type": "object",
                           "properties": ["fix": ["type": "boolean"]]]),
    ]

    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }

    static func dispatch(name: String, arguments: [String: Value]) async throws -> String {
        func str(_ key: String) -> String? {
            arguments[key]?.stringValue
        }

        let home = AgeOSHome()
        let engine = try SyncEngine(home: home)
        let adapters = try AdapterRegistry(home: home)

        switch name {
        case "search_skills":
            guard let query = str("query") else {
                throw AgeOSError(.conflict, "Missing the query parameter")
            }
            let local = try engine.index.listSkills().filter {
                $0.id.localizedCaseInsensitiveContains(query)
                    || $0.description.localizedCaseInsensitiveContains(query)
            }.map { ["id": $0.id, "description": String($0.description.prefix(160)), "version": $0.version] }
            let remote = await SkillsShSource().search(query, limit: 10)
            struct Out: Encodable {
                var library: [[String: String]]
                var skillsSh: [SkillsShSource.Hit]
            }
            return try json(Out(library: local, skillsSh: remote))

        case "skill_info":
            guard let query = str("skill") else {
                throw AgeOSError(.conflict, "Missing the skill parameter")
            }
            let row = try engine.index.resolveSkill(query: query)
            let parsed = try SkillParser.parse(directory: URL(fileURLWithPath: row.path, isDirectory: true))
            let sources = try engine.registry.load()
            let source = sources.first { $0.id == row.sourceId }
            let score = QualityScorer().score(.init(parsed: parsed, sourceStars: source?.stars,
                                                    sourcePushedAt: source?.pushedAt,
                                                    sourceLicense: source?.license))
            let lint = DescriptionLinter.lint(name: parsed.manifest.name,
                                              description: parsed.manifest.description)
            struct Out: Encodable {
                var id: String
                var description: String
                var version: String
                var deprecated: Bool
                var quality: QualityScorer.Score
                var lint: [DescriptionLinter.Finding]
            }
            return try json(Out(id: row.id, description: row.description, version: row.version,
                                deprecated: row.deprecated, quality: score, lint: lint))

        case "install_skill":
            guard let source = str("source") else {
                throw AgeOSError(.conflict, "Missing the source parameter (github owner/repo, or a path)")
            }
            let (descriptor, report) = try await engine.addSource(source)
            struct Out: Encodable {
                var source: String
                var version: String
                var installed: [String]
                var skipped: Int
            }
            return try json(Out(source: descriptor.id, version: report.version,
                                installed: report.installed, skipped: report.skippedCount))

        case "enable_skill", "disable_skill":
            guard let skill = str("skill"), let target = str("target") else {
                throw AgeOSError(.conflict, "Missing the skill or target parameter")
            }
            let project = str("project").map { URL(fileURLWithPath: $0, isDirectory: true) }
            let linkEngine = LinkEngine(home: home, store: engine.store, adapters: adapters)
            if name == "enable_skill" {
                let row = try engine.index.resolveSkill(query: skill)
                guard let ref = SkillRef(id: row.id) else {
                    throw AgeOSError(.notFound, "Invalid id: \(row.id)")
                }
                return try json(try linkEngine.enable(ref, sourceId: row.sourceId,
                                                      adapterId: target, project: project))
            } else {
                let lock = try Lockfile.load(from: home.lockfilePath)
                let id = lock.skills[skill] != nil ? skill
                    : (lock.skills.keys.first { $0.hasSuffix("/\(skill)") } ?? skill)
                guard let ref = SkillRef(id: id) else {
                    throw AgeOSError(.notFound, "Invalid id: \(id)")
                }
                return try json(try linkEngine.disable(ref, adapterId: target, project: project))
            }

        case "list_targets":
            struct Row: Encodable {
                var id: String
                var displayName: String
                var detected: Bool
                var skills: Bool
                var mcp: Bool
                var verified: Bool
            }
            let rows = adapters.adapters.map {
                Row(id: $0.id, displayName: $0.displayName, detected: $0.isDetected(),
                    skills: $0.skills != nil, mcp: $0.mcp != nil,
                    verified: ($0.skills?.verified ?? $0.mcp?.verified) ?? false)
            }
            return try json(rows)

        case "scan_library":
            let report = try ScanEngine(home: home, adapters: adapters, index: engine.index).run()
            return try json(report)

        case "budget_report":
            let index = engine.index
            let meter = BudgetMeter(adapters: adapters,
                                    mcpSchemaTokens: { try? index.mcpSchemaTokens(entryName: $0) })
            let ids = str("target").map { [$0] }
                ?? adapters.detected().filter { $0.skills != nil || $0.mcp != nil }.map(\.id)
            var reports: [BudgetMeter.Report] = []
            for id in ids {
                reports.append(try meter.compute(adapterId: id))
            }
            return try json(reports)

        case "doctor":
            let fix = arguments["fix"]?.boolValue ?? false
            let doctor = Doctor(home: home, store: engine.store, adapters: adapters)
            return try json(try doctor.run(fix: fix))

        default:
            throw AgeOSError(.notFound, "No such tool: \(name)")
        }
    }
}
