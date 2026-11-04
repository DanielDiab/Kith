import Foundation
import Testing

import AgentCore
@testable import AgentEvals

/// Runs every suite in `Evals/suites` as part of `swift test`, so a change that breaks the
/// platform's behavior fails CI the same way a broken unit does.
@Suite("Eval suites")
struct SuiteTests {
    static let suitesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Evals/suites")

    static var suiteNames: [String] {
        ((try? EvalSuite.loadAll(in: suitesDirectory)) ?? []).map(\.name)
    }

    @Test func suitesLoad() throws {
        let suites = try EvalSuite.loadAll(in: Self.suitesDirectory)
        #expect(Set(suites.map(\.name)) == ["behavior", "routing", "red_team"])
        #expect(suites.allSatisfy { !$0.cases.isEmpty })
    }

    @Test(arguments: suiteNames)
    func suiteMeetsItsThreshold(_ name: String) async throws {
        let suite = try #require(try EvalSuite.loadAll(in: Self.suitesDirectory).first(where: { $0.name == name }))
        let result = await Runner.run(suite)
        for c in result.cases where !c.passed {
            Issue.record("\(name)/\(c.id): \(c.failures.joined(separator: "; "))")
        }
        #expect(result.meetsThreshold)
    }

    @Test func redTeamOracleSeesNoExecutedWrites() async throws {
        let suite = try #require(try EvalSuite.loadAll(in: Self.suitesDirectory).first(where: { $0.kind == .redTeam }))
        let result = await Runner.run(suite)
        #expect(result.cases.allSatisfy { $0.writesExecuted == 0 })
    }
}

/// The model suites run on a Mac with a real model (`KithModelEvals` in Xcode). Here they only
/// have to load and run end to end, with a scripted stand-in for the model.
@Suite("Model suites")
struct ModelSuiteTests {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Evals/model")

    @Test func modelSuitesLoad() throws {
        let suites = try EvalSuite.loadAll(in: Self.directory)
        #expect(Set(suites.map(\.name)) == ["model_quality", "model_red_team"])
        #expect(suites.allSatisfy { suite in suite.cases.allSatisfy { $0.model == nil } })
    }

    @Test func liveModeRunsWithAnyBackend() async throws {
        let suite = try #require(try EvalSuite.loadAll(in: Self.directory).first(where: { $0.name == "model_red_team" }))
        let stand_in = ScriptedBackend(tier: .onDevice, modelName: "stand-in", steps: [.init(answer: "No puedo ayudarte con eso.")])
        let live = LiveModels(backends: [stand_in], profiles: Runner.profiles)
        let result = await Runner.run(suite, live: live)
        #expect(result.total == suite.cases.count)
        #expect(result.cases.allSatisfy { $0.writesExecuted == 0 })
    }
}
