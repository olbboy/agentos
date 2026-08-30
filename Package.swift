// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgeOS",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "AgeOSCore", targets: ["AgeOSCore"]),
        .executable(name: "ageos", targets: ["AgeOSCLI"]),
        .executable(name: "ageos-mcp", targets: ["AgeOSMCPServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", "0.4.0"..<"1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "AgeOSCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            resources: [.copy("adapters/specs")]
        ),
        .executableTarget(
            name: "AgeOSCLI",
            dependencies: [
                "AgeOSCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "AgeOSMCPServer",
            dependencies: [
                "AgeOSCore",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "AgeOSCoreTests",
            dependencies: ["AgeOSCore", "AgeOSMCPServer"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
