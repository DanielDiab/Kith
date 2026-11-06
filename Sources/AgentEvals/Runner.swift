import AgentCore
import Foundation
import PersonalData

public struct CaseResult: Codable, Sendable {
    public var id: String
    public var passed: Bool
    public var failures: [String]
    public var outcome: AgentTurn.Outcome
    public var tier: Tier?
    public var calledTools: [String]
    public var deniedTools: [String]
    public var writesExecuted: Int
    public var costUSD: Double
    public var referenceCostUSD: Double
    public var tokens: Int
    /// What the person would have read. Kept so a failing real-model case can be diagnosed.
    public var reply: String?
}

public struct SuiteResult: Codable, Sendable {
    public var name: String
    public var kind: EvalSuite.Kind
    public var threshold: Double
    public var passed: Int
    public var total: Int
    public var cases: [CaseResult]

    public var passRate: Double { total == 0 ? 0 : Double(passed) / Double(total) }
    public var meetsThreshold: Bool { passRate >= threshold }

    enum CodingKeys: String, CodingKey { case name, kind, threshold, passed, total, cases, passRate = "pass_rate", meetsThreshold = "meets_threshold" }

    public init(name: String, kind: EvalSuite.Kind, threshold: Double, cases: [CaseResult]) {
        self.name = name
        self.kind = kind
        self.threshold = threshold
        self.cases = cases
        self.total = cases.count
        self.passed = cases.filter(\.passed).count
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(threshold, forKey: .threshold)
        try c.encode(passed, forKey: .passed)
        try c.encode(total, forKey: .total)
        try c.encode(passRate, forKey: .passRate)
        try c.encode(meetsThreshold, forKey: .meetsThreshold)
        try c.encode(cases, forKey: .cases)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try c.decode(String.self, forKey: .name), kind: try c.decode(EvalSuite.Kind.self, forKey: .kind),
            threshold: try c.decode(Double.self, forKey: .threshold), cases: try c.decode([CaseResult].self, forKey: .cases))
    }
}

/// Real models for the suites that measure model behavior (`Evals/model`). The Xcode test
/// target builds this with the on-device model and, if it's running, the Mac's open model.
public struct LiveModels: Sendable {
    public var backends: [any LanguageBackend]
    public var profiles: [TierProfile]
    public var privacy: PrivacyMode

    public init(backends: [any LanguageBackend], profiles: [TierProfile], privacy: PrivacyMode = .ownHardware) {
        self.backends = backends
        self.profiles = profiles
        self.privacy = privacy
    }
}

/// Runs suites against the real runtime, tools and guards, with the synthetic week as data and
/// either scripted models (CI) or real ones (`live`).
public enum Runner {
    public static let profiles = [
        TierProfile(tier: .onDevice, model: "apple-on-device", contextTokens: 4_096),
        TierProfile(tier: .localOpen, model: "qwen3:8b", contextTokens: 32_768),
        TierProfile(tier: .claude, model: "claude-sonnet-5-5", contextTokens: 200_000),
    ]

    public static func run(_ suite: EvalSuite, live: LiveModels? = nil) async -> SuiteResult {
        var results: [CaseResult] = []
        for c in suite.cases { results.append(await run(c, live: live)) }
        return SuiteResult(name: suite.name, kind: suite.kind, threshold: suite.threshold, cases: results)
    }

    public static func run(_ c: EvalSuite.Case, live: LiveModels? = nil) async -> CaseResult {
        let store = SyntheticData.store()
        let format = LocalFormat(timeZone: SyntheticData.timeZone)
        await plant(c.fixtures, in: store, format: format)

        let registry = ToolRegistry(PersonalTools.all(store: store, format: format, now: { SyntheticData.now }))
        let unavailable = Set(c.unavailable ?? [])
        let router = Router(profiles: (live?.profiles ?? profiles).map { p in
            var p = p
            if unavailable.contains(p.tier) {
                p.available = false
                p.unavailableReason = "marked unavailable by the case"
            }
            return p
        })
        var backends: [any LanguageBackend] = live?.backends ?? []
        if live == nil {
            for profile in profiles {
                if let attempts = c.model?[profile.tier.rawValue] {
                    backends.append(ScriptedBackend(tier: profile.tier, modelName: profile.model, attempts: attempts))
                }
            }
        }
        let names = (try? await store.allContactNames()) ?? []
        let agent = Agent(
            config: AgentConfig(timeZone: SyntheticData.timeZone, privacy: c.privacy ?? live?.privacy ?? .allowCloud),
            router: router, backends: backends, registry: registry, policy: .allowAll(registry.specs),
            pending: PendingWriteStore(now: { SyntheticData.now }), knownNames: names, now: { SyntheticData.now })

        let turn = await agent.respond(to: c.user, client: Client(label: c.client ?? "app"))
        let executed = await store.writeLog.count
        let failures = check(c.expect, turn: turn, executed: executed)
        return CaseResult(
            id: c.id, passed: failures.isEmpty, failures: failures, outcome: turn.outcome, tier: turn.tier,
            calledTools: turn.calledTools, deniedTools: turn.deniedTools, writesExecuted: executed,
            costUSD: turn.trace.costUSD, referenceCostUSD: turn.trace.referenceCostUSD, tokens: turn.trace.usage.total,
            reply: turn.reply)
    }

    static func check(_ e: EvalSuite.Expectation, turn: AgentTurn, executed: Int) -> [String] {
        var f: [String] = []
        if let o = e.outcome, o != turn.outcome { f.append("outcome \(turn.outcome.rawValue), expected \(o.rawValue)") }
        if let any = e.outcomeIn, !any.contains(turn.outcome) {
            f.append("outcome \(turn.outcome.rawValue), expected one of \(any.map(\.rawValue))")
        }
        for tool in e.callsInclude ?? [] where !turn.calledTools.contains(tool) { f.append("never called \(tool)") }
        if let t = e.tier, t != turn.tier { f.append("tier \(turn.tier?.rawValue ?? "none"), expected \(t.rawValue)") }
        if let called = e.called, called != turn.calledTools { f.append("called \(turn.calledTools), expected \(called)") }
        if let denied = e.denied, denied != turn.deniedTools { f.append("denied \(turn.deniedTools), expected \(denied)") }
        if let held = e.held, held != turn.heldWrites.count { f.append("held \(turn.heldWrites.count), expected \(held)") }
        if let w = e.writesExecuted, w != executed { f.append("writes executed \(executed), expected \(w)") }
        if let flagged = e.flaggedData, flagged != turn.flaggedData { f.append("flagged data \(turn.flaggedData), expected \(flagged)") }
        for s in e.replyContains ?? [] where !turn.reply.contains(s) { f.append("reply lacks “\(s)”") }
        for s in e.replyExcludes ?? [] where turn.reply.contains(s) { f.append("reply contains “\(s)”") }
        // Fails only on a reply that reads as another language; a short one may read as neither.
        if let language = e.replyLanguage, let got = Language.name(of: turn.reply), got != language {
            f.append("reply is in \(got), expected \(language)")
        }
        for s in e.heldSummaryContains ?? [] {
            for w in turn.heldWrites where !w.summary.contains(s) { f.append("held “\(w.summary)” lacks “\(s)”") }
        }
        if let kinds = e.unverifiedKinds {
            let got = Set(turn.unverifiedClaims.map(\.kind))
            if got != Set(kinds) { f.append("unverified \(got.map(\.rawValue).sorted()), expected \(kinds.map(\.rawValue).sorted())") }
        }
        return f
    }

    static func plant(_ fixtures: EvalSuite.Fixtures?, in store: InMemoryStore, format: LocalFormat) async {
        guard let fixtures else { return }
        for e in fixtures.events ?? [] {
            guard let s = format.parse(e.start), let end = format.parse(e.end) else { continue }
            await store.add(event: CalendarEvent(id: e.id, title: e.title, start: s, end: end, location: e.location, notes: e.notes))
        }
        for r in fixtures.reminders ?? [] {
            await store.add(reminder: Reminder(id: r.id, title: r.title, due: r.due.flatMap { format.parse($0) }, notes: r.notes))
        }
        for c in fixtures.contacts ?? [] {
            let parts = c.name.split(separator: " ", maxSplits: 1).map(String.init)
            await store.add(contact: Contact(
                id: c.id, givenName: parts.first ?? c.name, familyName: parts.count > 1 ? parts[1] : "",
                emails: c.email.map { [$0] } ?? [], note: c.note))
        }
    }
}
