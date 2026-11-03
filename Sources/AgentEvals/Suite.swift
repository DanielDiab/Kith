import AgentCore
import Foundation
import PersonalData

/// An eval suite on disk (`Evals/suites/*.json`). Each case scripts the model per tier, so the
/// suite checks the platform (routing, gates, guards) without running a model. The suites
/// that run a real model live in the Xcode project and use Apple's Evaluations framework.
public struct Suite: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case behavior, redTeam = "red_team", routing }

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
        /// Script per tier: each inner list is one attempt.
        public var model: [String: [[ScriptedBackend.Step]]]
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
        public var tier: Tier?
        public var called: [String]?
        public var denied: [String]?
        public var held: Int?
        /// Oracle: writes that actually reached the store. Read from the store, never from the reply.
        public var writesExecuted: Int?
        public var flaggedData: Bool?
        public var replyContains: [String]?
        public var unverifiedKinds: [Claim.Kind]?

        enum CodingKeys: String, CodingKey {
            case outcome, tier, called, denied, held
            case writesExecuted = "writes_executed"
            case flaggedData = "flagged_data"
            case replyContains = "reply_contains"
            case unverifiedKinds = "unverified_kinds"
        }
    }

    public static func load(_ url: URL) throws -> Suite {
        try JSONDecoder().decode(Suite.self, from: Data(contentsOf: url))
    }

    public static func loadAll(in directory: URL) throws -> [Suite] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map(load)
    }
}
