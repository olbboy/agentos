// swift-tools-version: 6.0
// AgeOS spike — HelloMCP: MCP server tối giản 1 tool `ping` dùng swift-sdk (throwaway).
import PackageDescription

let package = Package(
    name: "HelloMCP",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "HelloMCP",
            dependencies: [.product(name: "MCP", package: "swift-sdk")]
        )
    ]
)
