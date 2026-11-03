import Foundation
import Testing

@testable import AgentCore

let readSpec = ToolSpec(name: "calendar_list_events", description: "", effect: .read)
let writeSpec = ToolSpec(name: "calendar_create_event", description: "", effect: .write)

@Suite("Permissions")
struct PermissionTests {
    @Test func deniesToolsWithoutAGrant() {
        let policy = PermissionPolicy()
        guard case .deny = policy.decide(readSpec, for: .app) else {
            Issue.record("expected deny")
            return
        }
    }

    @Test func scopesToolsByClient() {
        let policy = PermissionPolicy(grants: [
            readSpec.name: ToolGrant(scope: .mcpClients(["claude-desktop"])),
            writeSpec.name: ToolGrant(scope: .onDevice),
        ])
        #expect(policy.decide(readSpec, for: .mcp("claude-desktop")) == .allow)
        #expect(policy.decide(readSpec, for: .app) == .allow)
        guard case .deny = policy.decide(readSpec, for: .mcp("other")) else {
            Issue.record("expected deny for an unlisted client")
            return
        }
        guard case .deny = policy.decide(writeSpec, for: .mcp("claude-desktop")) else {
            Issue.record("expected deny for an on-device-only tool")
            return
        }
    }

    @Test func alwaysHoldsWrites() {
        let policy = PermissionPolicy.allowAll([readSpec, writeSpec])
        #expect(policy.decide(writeSpec, for: .app) == .holdForConfirmation)
        #expect(policy.decide(writeSpec, for: .siri) == .holdForConfirmation)
        #expect(policy.decide(readSpec, for: .mcp("x")) == .allow)
    }

    @Test func pendingWritesExpireAndResolveOnce() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_000))
        let store = PendingWriteStore(ttl: 60, now: { clock.now })
        let w = await store.hold(tool: "t", arguments: [:], summary: "s", client: .app, proposedAfterFlaggedData: false)
        #expect(await store.all().count == 1)
        _ = try await store.take(w.id)
        await #expect(throws: PendingWriteError.notFound) { try await store.take(w.id) }

        let late = await store.hold(tool: "t", arguments: [:], summary: "s", client: .app, proposedAfterFlaggedData: false)
        clock.advance(61)
        await #expect(throws: PendingWriteError.expired) { try await store.take(late.id) }
    }
}

/// A settable clock for tests.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(start: Date) { current = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }
}
