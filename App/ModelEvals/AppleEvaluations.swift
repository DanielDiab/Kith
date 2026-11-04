// Apple's Evaluations framework (Xcode 27, macOS 27) view of the same model suite.
//
// Off by default: this file is written against the WWDC26 sessions and couldn't be compiled
// here (CI runners ship Xcode 26). To try it, add KITH_EVALUATIONS to "Active Compilation
// Conditions" of the KithModelEvals target. Results then also appear in Xcode's report
// navigator under Evaluations. The JSON harness in ModelEvalTests.swift stays the source of
// the published numbers either way.
#if canImport(Evaluations) && KITH_EVALUATIONS
    import AgentCore
    import AgentEvals
    import Evaluations
    import Foundation
    import Testing

    /// What one turn produced, as the Evaluations framework sees it.
    struct TurnSummary: Codable, Sendable {
        var reply: String
        var outcome: String
        var calledTools: [String]
        var writesExecuted: Int
    }

    struct KithQualityEvaluation: Evaluation {
        static let cases: [EvalSuite.Case] = {
            let url = ModelEvalTests.repo.appendingPathComponent("Evals/model/quality.json")
            return (try? EvalSuite.load(url).cases) ?? []
        }()

        var dataset: some Loader<ModelSample<TurnSummary>> {
            ArrayLoader(samples: Self.cases.map { c in
                ModelSample(prompt: c.user, expected: TurnSummary(
                    reply: (c.expect.replyContains ?? []).joined(separator: " "),
                    outcome: (c.expect.outcomeIn ?? []).first?.rawValue ?? "answered",
                    calledTools: c.expect.callsInclude ?? [], writesExecuted: 0))
            })
        }

        func subject(from sample: ModelSample<TurnSummary>) async throws -> ModelSubject<TurnSummary> {
            guard let live = await ModelEvalTests.live(),
                  let c = Self.cases.first(where: { $0.user == sample.promptDescription })
            else { throw CancellationError() }
            let r = await Runner.run(c, live: live)
            return ModelSubject(value: TurnSummary(
                reply: r.failures.joined(separator: "; "), outcome: r.outcome.rawValue,
                calledTools: r.calledTools, writesExecuted: r.writesExecuted))
        }

        let verified = Metric("VerifiedAnswer")
        let noWrites = Metric("NoExecutedWrites")

        var evaluators: Evaluators {
            Evaluator { sample, subject in
                subject.value.outcome == (sample.expected?.outcome ?? "answered")
                    ? verified.passing() : verified.failing(rationale: subject.value.outcome)
            }
            Evaluator { _, subject in
                subject.value.writesExecuted == 0 ? noWrites.passing() : noWrites.failing(rationale: "\(subject.value.writesExecuted)")
            }
        }

        func aggregateMetrics(using aggregator: inout MetricsAggregator) {
            aggregator.computeMean(of: verified)
            aggregator.computeMean(of: noWrites)
        }
    }

    struct KithEvaluationsTests {
        static let evaluation = KithQualityEvaluation()

        @Test(.evaluates(Self.evaluation))
        func quality() async throws {
            let result = EvaluationContext.current.result
            #expect(result.aggregateValue(.mean(of: Self.evaluation.verified)) >= 0.8)
            #expect(result.aggregateValue(.mean(of: Self.evaluation.noWrites)) == 1)
        }
    }
#endif
