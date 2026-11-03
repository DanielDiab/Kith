import Foundation

/// A write the agent proposed and nobody has confirmed yet.
public struct PendingWrite: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var tool: String
    public var arguments: JSONValue
    /// What the person reads before saying yes. Built by the tool, never by the model.
    public var summary: String
    public var client: Client
    public var createdAt: Date
    public var expiresAt: Date
    /// The turn that proposed this write had read data containing planted instructions.
    /// The app shows a warning on the confirmation card.
    public var proposedAfterFlaggedData: Bool
}

public enum PendingWriteError: Error, Equatable, Sendable {
    case notFound
    case expired
}

/// Holds proposed writes until the person confirms or rejects them in the app.
///
/// Confirmation is only exposed to the app's UI. An MCP client can propose a write but
/// cannot confirm it: otherwise a model could approve its own action.
public actor PendingWriteStore {
    private var pending: [String: PendingWrite] = [:]
    private var counter = 0
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    public init(ttl: TimeInterval = 600, now: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttl
        self.now = now
    }

    public func hold(
        tool: String, arguments: JSONValue, summary: String, client: Client, proposedAfterFlaggedData: Bool
    ) -> PendingWrite {
        counter += 1
        let created = now()
        let write = PendingWrite(
            id: "w\(counter)",
            tool: tool,
            arguments: arguments,
            summary: summary,
            client: client,
            createdAt: created,
            expiresAt: created.addingTimeInterval(ttl),
            proposedAfterFlaggedData: proposedAfterFlaggedData
        )
        pending[write.id] = write
        return write
    }

    /// Removes the write and returns it so the caller can execute it.
    public func take(_ id: String) throws -> PendingWrite {
        guard let write = pending.removeValue(forKey: id) else { throw PendingWriteError.notFound }
        guard write.expiresAt > now() else { throw PendingWriteError.expired }
        return write
    }

    public func reject(_ id: String) throws {
        guard pending.removeValue(forKey: id) != nil else { throw PendingWriteError.notFound }
    }

    public func all() -> [PendingWrite] {
        pending.values.sorted { $0.createdAt < $1.createdAt || ($0.createdAt == $1.createdAt && $0.id < $1.id) }
    }
}
