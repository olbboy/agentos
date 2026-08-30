// AgeOS spike — MCP server stdio tối giản: 1 tool `ping` (throwaway, không merge vào core).
import Foundation
import MCP

@main
struct HelloMCPMain {
    static func main() async throws {
        let server = Server(
            name: "ageos-spike-hello-mcp",
            version: "0.1.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                Tool(
                    name: "ping",
                    description: "Health probe. Returns pong plus the echoed text.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "echo": ["type": "string", "description": "Text to echo back"]
                        ]
                    ]
                )
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            guard params.name == "ping" else {
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }
            let echo = params.arguments?["echo"]?.stringValue ?? ""
            return CallTool.Result(content: [.text("pong \(echo)")])
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
