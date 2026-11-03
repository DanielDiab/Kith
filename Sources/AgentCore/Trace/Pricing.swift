import Foundation

public struct ModelPrice: Codable, Sendable, Equatable {
    /// US dollars per million tokens.
    public var input: Double
    public var cachedInput: Double
    public var output: Double

    public init(input: Double, cachedInput: Double, output: Double) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
    }

    public func cost(_ usage: TokenUsage) -> Double {
        let uncached = max(0, usage.input - usage.cachedInput)
        let out = usage.output + usage.reasoning
        return (Double(uncached) * input + Double(usage.cachedInput) * cachedInput + Double(out) * output) / 1_000_000
    }
}

/// What each call costs, and what it would have cost on the reference cloud model.
///
/// On-device and local models cost nothing, so a cost column of zeros says nothing about
/// the router. The reference cost answers the useful question: how much did routing save
/// compared with sending every call to Claude? Same idea as Charter's reference cost for
/// local Ollama models.
public struct PriceBook: Codable, Sendable, Equatable {
    public var prices: [String: ModelPrice]
    public var referenceModel: String

    public init(prices: [String: ModelPrice], referenceModel: String) {
        self.prices = prices
        self.referenceModel = referenceModel
    }

    public func cost(model: String, tier: Tier, usage: TokenUsage) -> Double {
        guard tier == .claude else { return 0 }
        return prices[model]?.cost(usage) ?? 0
    }

    public func referenceCost(_ usage: TokenUsage) -> Double {
        prices[referenceModel]?.cost(usage) ?? 0
    }

    /// Standard Claude API prices, USD per million tokens, from
    /// https://platform.claude.com/docs/en/about-claude/pricing (checked 2026-11-03).
    public static let claude2026 = PriceBook(
        prices: [
            "claude-haiku-5-5": ModelPrice(input: 0.10, cachedInput: 0.01, output: 0.50),
            "claude-sonnet-5-5": ModelPrice(input: 2, cachedInput: 0.10, output: 10),
            "claude-opus-5-5": ModelPrice(input: 4, cachedInput: 0.20, output: 20),
        ],
        referenceModel: "claude-sonnet-5-5"
    )
}
