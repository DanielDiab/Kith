import Foundation

/// One step of a turn: a guard, the routing decision, a model call, a tool call.
/// The app's trace view draws one row per span, like `AgentTrace.tsx` on the portfolio.
public struct Span: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case inputGuard, route, model, tool, dataGuard, outputGuard, confirmation
    }

    public enum Status: String, Codable, Sendable {
        case ok, blocked, held, denied, flagged, failed, retried, escalated
    }

    public var id: Int
    public var kind: Kind
    public var name: String
    public var status: Status
    public var startedAt: Date
    public var durationMs: Double
    public var tier: Tier?
    public var model: String?
    public var usage: TokenUsage?
    public var costUSD: Double
    public var referenceCostUSD: Double
    /// Free-form details, PII masked before they get here.
    public var detail: [String: String]
}

public struct Trace: Codable, Sendable, Equatable {
    public var id: String
    public var client: Client
    public var userText: String
    public var startedAt: Date
    public var spans: [Span]

    public var tier: Tier? { spans.last(where: { $0.kind == .model })?.tier }
    public var usage: TokenUsage { spans.compactMap(\.usage).reduce(.zero, +) }
    public var costUSD: Double { spans.reduce(0) { $0 + $1.costUSD } }
    public var referenceCostUSD: Double { spans.reduce(0) { $0 + $1.referenceCostUSD } }
    public var latencyMs: Double { spans.reduce(0) { $0 + $1.durationMs } }
}

/// Collects spans for one turn. An actor because tool calls may arrive from a backend's own
/// concurrent loop (Foundation Models runs tools itself).
public actor TraceRecorder {
    private var spans: [Span] = []
    private let masker: PIIMasker
    private let prices: PriceBook
    private let now: @Sendable () -> Date

    public init(masker: PIIMasker, prices: PriceBook, now: @escaping @Sendable () -> Date = { Date() }) {
        self.masker = masker
        self.prices = prices
        self.now = now
    }

    public func time() -> Date { now() }

    @discardableResult
    public func record(
        _ kind: Span.Kind, _ name: String, status: Span.Status = .ok, startedAt: Date,
        tier: Tier? = nil, model: String? = nil, usage: TokenUsage? = nil, detail: [String: String] = [:]
    ) -> Span {
        let end = now()
        let cost = (tier != nil && model != nil && usage != nil) ? prices.cost(model: model!, tier: tier!, usage: usage!) : 0
        let reference = usage.map { prices.referenceCost($0) } ?? 0
        let span = Span(
            id: spans.count + 1,
            kind: kind,
            name: name,
            status: status,
            startedAt: startedAt,
            durationMs: max(0, end.timeIntervalSince(startedAt) * 1000),
            tier: tier,
            model: model,
            usage: usage,
            costUSD: cost,
            referenceCostUSD: reference,
            detail: detail.mapValues { masker.mask($0) }
        )
        spans.append(span)
        return span
    }

    public func all() -> [Span] { spans }
}

/// Recent traces from every client (app, Siri, MCP), newest last. The app's trace view and
/// the MCP activity list read from here.
public actor TraceLog {
    private var traces: [Trace] = []
    private let capacity: Int
    private var continuations: [UUID: AsyncStream<Trace>.Continuation] = [:]

    public init(capacity: Int = 200) {
        self.capacity = capacity
    }

    public func append(_ trace: Trace) {
        traces.append(trace)
        if traces.count > capacity { traces.removeFirst(traces.count - capacity) }
        for c in continuations.values { c.yield(trace) }
    }

    public func recent(_ n: Int = 50) -> [Trace] { Array(traces.suffix(n)) }

    /// New traces as they arrive.
    public func updates() -> AsyncStream<Trace> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Trace>.makeStream()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }
        return stream
    }

    private func remove(_ id: UUID) { continuations[id] = nil }
}
