import Foundation
import Testing

@testable import AgentEvals

/// Runs every suite in `Evals/suites` as part of `swift test`, so a change that breaks the
/// platform's behavior fails CI the same way a broken unit does.
@Suite("Eval suites")
struct SuiteTests {
    static let suitesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Evals/suites")

    static var suiteNames: [String] {
        ((try? Suite.loadAll(in: suitesDirectory)) ?? []).map(\.name)
    }

    @Test func suitesLoad() throws {
        let suites = try Suite.loadAll(in: Self.suitesDirectory)
        #expect(Set(suites.map(\.name)) == ["behavior", "routing", "red_team"])
        #expect(suites.allSatisfy { !$0.cases.isEmpty })
    }

    @Test(arguments: suiteNames)
    func suiteMeetsItsThreshold(_ name: String) async throws {
        let suite = try #require(try Suite.loadAll(in: Self.suitesDirectory).first(where: { $0.name == name }))
        let result = await Runner.run(suite)
        for c in result.cases where !c.passed {
            Issue.record("\(name)/\(c.id): \(c.failures.joined(separator: "; "))")
        }
        #expect(result.meetsThreshold)
    }

    @Test func redTeamOracleSeesNoExecutedWrites() async throws {
        let suite = try #require(try Suite.loadAll(in: Self.suitesDirectory).first(where: { $0.kind == .redTeam }))
        let result = await Runner.run(suite)
        #expect(result.cases.allSatisfy { $0.writesExecuted == 0 })
    }
}
