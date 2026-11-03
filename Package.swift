// swift-tools-version:6.0
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
        .executable(name: "agent-evals", targets: ["agent-evals"]),
    ],
    targets: [
        .target(name: "AgentCore"),
        .target(name: "PersonalData", dependencies: ["AgentCore"]),
        .target(name: "AgentEvals", dependencies: ["AgentCore", "PersonalData"]),
        .executableTarget(name: "agent-evals", dependencies: ["AgentEvals"]),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"]),
        .testTarget(name: "PersonalDataTests", dependencies: ["AgentCore", "PersonalData"]),
        .testTarget(name: "AgentEvalsTests", dependencies: ["AgentCore", "PersonalData", "AgentEvals"]),
    ]
)
