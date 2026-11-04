// swift-tools-version:6.1
//
// The core of the agent: routing, guards, permissions, held writes, traces and the
// eval harness. None of it imports an Apple-only framework, so `swift test` runs the
// whole suite on Linux CI without a model. The SwiftUI apps, the EventKit adapter and
// the Foundation Models backends live on top of this package and build in Xcode.

import PackageDescription

let package = Package(
    name: "AgentKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "AgentCore", targets: ["AgentCore"]),
        .library(name: "PersonalData", targets: ["PersonalData"]),
        .library(name: "AgentEvals", targets: ["AgentEvals"]),
        .library(name: "ModelBackends", targets: ["ModelBackends"]),
        .library(name: "KithMCP", targets: ["KithMCP"]),
        .library(name: "AppleData", targets: ["AppleData"]),
        .executable(name: "agent-evals", targets: ["agent-evals"]),
        .executable(name: "kith-mcp", targets: ["kith-mcp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.4.0"),
    ],
    targets: [
        .target(name: "AgentCore"),
        .target(name: "PersonalData", dependencies: ["AgentCore"]),
        .target(name: "AgentEvals", dependencies: ["AgentCore", "PersonalData"]),
        .target(name: "ModelBackends", dependencies: ["AgentCore"]),
        .target(
            name: "KithMCP",
            dependencies: [
                "AgentCore", "PersonalData",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        ),
        // EventKit, Contacts and Foundation Models. Empty on Linux; built by the macOS CI job.
        .target(name: "AppleData", dependencies: ["AgentCore", "PersonalData"]),
        .executableTarget(name: "agent-evals", dependencies: ["AgentEvals"]),
        .executableTarget(name: "kith-mcp", dependencies: ["KithMCP"]),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"]),
        .testTarget(name: "PersonalDataTests", dependencies: ["AgentCore", "PersonalData"]),
        .testTarget(name: "AgentEvalsTests", dependencies: ["AgentCore", "PersonalData", "AgentEvals"]),
        .testTarget(name: "ModelBackendsTests", dependencies: ["AgentCore", "ModelBackends"]),
        .testTarget(
            name: "KithMCPTests",
            dependencies: [
                "AgentCore", "PersonalData", "KithMCP",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        ),
    ]
)
