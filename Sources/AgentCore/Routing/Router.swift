import Foundation

/// Where a model call runs, cheapest and most private first.
public enum Tier: String, Codable, Sendable, CaseIterable, Comparable {
    /// Apple's on-device model (Foundation Models `SystemLanguageModel`). Free, offline, 4K context.
    case onDevice
    /// A larger open model on the person's own Mac (MLX, or Ollama behind a chat-completions
    /// adapter). Free, data stays on hardware the person owns.
    case localOpen
    /// Claude as a server model (`ClaudeLanguageModel`). Paid, and data leaves the device.
    case claude

    var rank: Int {
        switch self {
        case .onDevice: return 0
        case .localOpen: return 1
        case .claude: return 2
        }
    }

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rank < rhs.rank }

    public var leavesDevice: Bool { self == .claude }
}

public struct TierProfile: Codable, Sendable, Equatable {
    public var tier: Tier
    public var model: String
    public var contextTokens: Int
    public var available: Bool
    /// Why it's unavailable, as reported by the backend ("Apple Intelligence is off").
    public var unavailableReason: String?

    public init(tier: Tier, model: String, contextTokens: Int, available: Bool = true, unavailableReason: String? = nil) {
        self.tier = tier
        self.model = model
        self.contextTokens = contextTokens
        self.available = available
        self.unavailableReason = unavailableReason
    }
}

/// How far the person lets their data travel.
public enum PrivacyMode: String, Codable, Sendable {
    /// Only Apple's on-device model.
    case deviceOnly
    /// On-device or the person's own Mac. Nothing leaves hardware they own.
    case ownHardware
    /// Claude is allowed when the request needs it.
    case allowCloud

    func allows(_ tier: Tier) -> Bool {
        switch self {
        case .deviceOnly: return tier == .onDevice
        case .ownHardware: return tier != .claude
        case .allowCloud: return true
        }
    }
}

public struct RouteDecision: Codable, Sendable, Equatable {
    public var tier: Tier
    public var model: String
    public var reason: String
    /// Every tier that was considered and why it was skipped.
    public var skipped: [String: String]
}

/// Picks a tier in code, before any model runs. The model never decides where it runs.
///
/// Rules, in order, for each tier from cheapest to most capable:
/// 1. skip it if it's unavailable on this device right now;
/// 2. skip it if the person's privacy mode doesn't allow it;
/// 3. skip it if the prompt plus a reserve for tool results and the answer doesn't fit
///    its context window;
/// 4. skip the on-device model for requests that need multi-step reasoning (a lexical
///    check, no model call).
/// The first tier that survives wins. If none does, the cheapest allowed and available tier
/// runs anyway and the decision says so, so the answer may be weaker but never leaks.
public struct Router: Sendable {
    public var profiles: [TierProfile]
    /// Tokens kept free for tool results and the answer.
    public var reserveTokens: Int

    public init(profiles: [TierProfile], reserveTokens: Int = 1_500) {
        self.profiles = profiles.sorted { $0.tier < $1.tier }
        self.reserveTokens = reserveTokens
    }

    public enum Complexity: String, Codable, Sendable { case simple, complex }

    static let complexSignals: [String] = [
        #"\b(?:compara|comparar|planifica|planear|planea|organiza|organizar|prioriza|priorizar|optimiza|analiza|resume\s+(?:mi|la|el)\s+(?:semana|mes)|por\s+que|que\s+me\s+recomiendas|conflictos?|choques?)\b"#,
        #"\b(?:compare|plan|organi[sz]e|prioriti[sz]e|optimi[sz]e|analy[sz]e|summari[sz]e\s+my\s+(?:week|month)|why|recommend|conflicts?|overlap\w*)\b"#,
    ]

    public static func complexity(of text: String) -> Complexity {
        let folded = Text.fold(text)
        if folded.count > 400 { return .complex }
        return complexSignals.contains { Text.firstMatch($0, in: folded) != nil } ? .complex : .simple
    }

    public func route(promptTokens: Int, userText: String, privacy: PrivacyMode, startingAbove floor: Tier? = nil) -> RouteDecision? {
        let complexity = Self.complexity(of: userText)
        var skipped: [String: String] = [:]
        var fallback: TierProfile?

        for p in profiles {
            if let floor, p.tier <= floor {
                skipped[p.tier.rawValue] = "already tried"
                continue
            }
            guard p.available else {
                skipped[p.tier.rawValue] = "unavailable: \(p.unavailableReason ?? "not ready")"
                continue
            }
            guard privacy.allows(p.tier) else {
                skipped[p.tier.rawValue] = "privacy mode \(privacy.rawValue) keeps data off \(p.tier.rawValue)"
                continue
            }
            if fallback == nil { fallback = p }
            let needed = promptTokens + reserveTokens
            guard needed <= p.contextTokens else {
                skipped[p.tier.rawValue] = "needs ~\(needed) tokens, context is \(p.contextTokens)"
                continue
            }
            if p.tier == .onDevice, complexity == .complex {
                skipped[p.tier.rawValue] = "multi-step request, beyond the small model"
                continue
            }
            let why = p.tier == .onDevice
                ? "simple request that fits on device"
                : "cheapest allowed tier that fits (\(complexity.rawValue) request, ~\(promptTokens) tokens)"
            return RouteDecision(tier: p.tier, model: p.model, reason: why, skipped: skipped)
        }
        if let f = fallback {
            return RouteDecision(
                tier: f.tier, model: f.model,
                reason: "no tier fits every rule; using the cheapest allowed one", skipped: skipped)
        }
        return nil
    }
}
