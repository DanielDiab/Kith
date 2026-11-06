import AgentCore
import Foundation
import PersonalData

/// An eval suite on disk (`Evals/suites/*.json`). Each case scripts the model per tier, so the
/// suite checks the platform (routing, gates, guards) without running a model. The suites
/// that run a real model live in the Xcode project and use Apple's Evaluations framework.
public struct EvalSuite: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case behavior, redTeam = "red_team", routing, quality }

    public var name: String
    public var description: String
    public var kind: Kind
    /// Minimum pass rate. Security suites use 1.0, as Charter's shared suites did.
    public var threshold: Double
    public var cases: [Case]

    public struct Case: Codable, Sendable {
        public var id: String
        public var user: String
        public var client: String?
        public var privacy: PrivacyMode?
        /// Extra data planted for this case, on top of the synthetic week.
        public var fixtures: Fixtures?
        /// Tiers whose backend is reported unavailable ("Apple Intelligence is off").
        public var unavailable: [Tier]?
        /// Script per tier: each inner list is one attempt. Empty in suites that run a real model.
        public var model: [String: [[ScriptedBackend.Step]]]?
        public var expect: Expectation
    }

    public struct Fixtures: Codable, Sendable {
        public var events: [FixtureEvent]?
        public var reminders: [FixtureReminder]?
        public var contacts: [FixtureContact]?
    }

    public struct FixtureEvent: Codable, Sendable {
        public var id: String
        public var title: String
        public var start: String
        public var end: String
        public var location: String?
        public var notes: String?
    }

    public struct FixtureReminder: Codable, Sendable {
        public var id: String
        public var title: String
        public var due: String?
        public var notes: String?
    }

    public struct FixtureContact: Codable, Sendable {
        public var id: String
        public var name: String
        public var email: String?
        public var note: String?
    }

    public struct Expectation: Codable, Sendable {
        public var outcome: AgentTurn.Outcome?
        /// For real models: any of these outcomes passes.
        public var outcomeIn: [AgentTurn.Outcome]?
        /// For real models: these tools must be among the calls (order and extras don't matter).
        public var callsInclude: [String]?
        public var tier: Tier?
        public var called: [String]?
        public var denied: [String]?
        public var held: Int?
        /// Oracle: writes that actually reached the store. Read from the store, never from the reply.
        public var writesExecuted: Int?
        public var flaggedData: Bool?
        public var replyContains: [String]?
        /// For real models: text the reply must not contain (an event from another day).
        public var replyExcludes: [String]?
        /// For real models: "Spanish" or "English". Fails when `Language.name(of:)` reads the reply as the other one.
        public var replyLanguage: String?
        /// Text every held write's summary must contain: the change the person asked for.
        public var heldSummaryContains: [String]?
        public var unverifiedKinds: [Claim.Kind]?

        enum CodingKeys: String, CodingKey {
            case outcome, tier, called, denied, held
            case outcomeIn = "outcome_in"
            case callsInclude = "calls_include"
            case writesExecuted = "writes_executed"
            case flaggedData = "flagged_data"
            case replyContains = "reply_contains"
            case replyExcludes = "reply_excludes"
            case replyLanguage = "reply_language"
            case heldSummaryContains = "held_summary_contains"
            case unverifiedKinds = "unverified_kinds"
        }
    }

    public static func load(_ url: URL) throws -> EvalSuite {
        try JSONDecoder().decode(EvalSuite.self, from: Data(contentsOf: url))
    }

    public static func loadAll(in directory: URL) throws -> [EvalSuite] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map(load)
    }
}
