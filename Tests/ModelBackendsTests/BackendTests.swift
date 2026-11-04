import AgentCore
import Foundation
import Testing

@testable import ModelBackends

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Plays back canned HTTP responses and records what was sent.
final class StubHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(String, Int)]
    private(set) var bodies: [JSONValue] = []
    private(set) var headers: [[String: String]] = []

    init(_ replies: [(String, Int)]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.lock()
        defer { lock.unlock() }
        if let body = request.httpBody, let json = try? JSONValue.parse(String(decoding: body, as: UTF8.self)) {
            bodies.append(json)
        }
        headers.append(request.allHTTPHeaderFields ?? [:])
        let (text, status) = replies.isEmpty ? ("{}", 500) : replies.removeFirst()
        return (Data(text.utf8), status)
    }
}

/// A gate over one read tool that returns a fixed value.
struct EchoTool: ToolHandler {
    let spec = ToolSpec(
        name: "calendar_list_events", description: "List events.", effect: .read,
        parameters: [ToolParameter("from", type: "date-time", description: "start")])
    func call(_ arguments: JSONValue) async throws -> JSONValue {
        ["events": [["title": "Odontólogo", "start": "2026-11-04T10:00:00-05:00"]], "from_was": arguments["from"] ?? .null]
    }
}

func makeGate() -> (ToolGate, ToolRegistry) {
    let registry = ToolRegistry([EchoTool()])
    let gate = ToolGate(
        registry: registry, policy: .allowAll(registry.specs), client: .app, pending: PendingWriteStore(),
        recorder: TraceRecorder(masker: PIIMasker(), prices: .claude2026), masker: PIIMasker(), userText: "¿qué tengo hoy?")
    return (gate, registry)
}

@Suite("Chat completions backend")
struct ChatCompletionsTests {
    @Test func runsTheToolLoopThroughTheGate() async throws {
        let stub = StubHTTP([
            (#"{"choices":[{"message":{"role":"assistant","content":"","tool_calls":[{"id":"c1","type":"function","function":{"name":"calendar_list_events","arguments":"{\"from\":\"2026-11-04\"}"}}]}}],"usage":{"prompt_tokens":300,"completion_tokens":20}}"#, 200),
            (#"{"choices":[{"message":{"role":"assistant","content":"<think>checking</think>Tienes Odontólogo a las 10:00."}}],"usage":{"prompt_tokens":420,"completion_tokens":15}}"#, 200),
        ])
        let (gate, registry) = makeGate()
        let backend = ChatCompletionsBackend(client: stub)
        let reply = try await backend.respond(
            to: ModelRequest(instructions: "rules", messages: [.user("¿qué tengo hoy?")], tools: registry.specs), tools: gate)
        #expect(reply.text == "Tienes Odontólogo a las 10:00.")
        #expect(reply.usage.input == 720)
        #expect(reply.usage.output == 35)
        #expect(await gate.calledTools == ["calendar_list_events"])
        let second = try #require(stub.bodies.last)
        let toolMessage = try #require(second["messages"]?.arrayValue?.last)
        #expect(toolMessage["role"]?.stringValue == "tool")
        #expect(toolMessage["content"]?.stringValue?.contains("2026-11-04") == true)
        #expect(stub.bodies.first?["tools"]?.arrayValue?.count == 1)
    }

    @Test func mapsHTTPFailuresToBackendErrors() async {
        let (gate, registry) = makeGate()
        let request = ModelRequest(instructions: "", messages: [.user("hola")], tools: registry.specs)
        await #expect(throws: BackendError.contextExceeded) {
            try await ChatCompletionsBackend(client: StubHTTP([("{\"error\":\"prompt exceeds context length\"}", 400)])).respond(to: request, tools: gate)
        }
        await #expect(throws: BackendError.rateLimited) {
            try await ChatCompletionsBackend(client: StubHTTP([("{}", 429)])).respond(to: request, tools: gate)
        }
    }

    @Test func reportsAvailability() async {
        let up = await ChatCompletionsBackend(client: StubHTTP([("{\"data\":[]}", 200)])).profile()
        #expect(up.available)
        let down = await ChatCompletionsBackend(client: StubHTTP([])).profile()
        #expect(!down.available)
    }
}

@Suite("Anthropic backend")
struct AnthropicTests {
    @Test func runsTheToolLoopAndCountsTokens() async throws {
        let stub = StubHTTP([
            (#"{"content":[{"type":"text","text":"Reviso."},{"type":"tool_use","id":"tu1","name":"calendar_list_events","input":{"from":"2026-11-04"}}],"stop_reason":"tool_use","usage":{"input_tokens":500,"output_tokens":40}}"#, 200),
            (#"{"content":[{"type":"text","text":"Tienes Odontólogo a las 10:00."}],"stop_reason":"end_turn","usage":{"input_tokens":650,"cache_read_input_tokens":400,"output_tokens":12}}"#, 200),
        ])
        let (gate, registry) = makeGate()
        let backend = AnthropicBackend(apiKey: "test-key", client: stub)
        let reply = try await backend.respond(
            to: ModelRequest(instructions: "rules", messages: [.user("¿qué tengo hoy?")], tools: registry.specs), tools: gate)
        #expect(reply.text == "Tienes Odontólogo a las 10:00.")
        #expect(reply.usage.input == 1_550)
        #expect(reply.usage.cachedInput == 400)
        #expect(stub.headers.first?["x-api-key"] == "test-key")
        let last = try #require(stub.bodies.last?["messages"]?.arrayValue?.last)
        #expect(last["content"]?.arrayValue?.first?["type"]?.stringValue == "tool_result")
        #expect(stub.bodies.first?["system"]?.stringValue == "rules")
    }

    @Test func isUnavailableWithoutAKey() async {
        #expect(!AnthropicBackend(apiKey: "").profile().available)
        let (gate, _) = makeGate()
        await #expect(throws: BackendError.self) {
            try await AnthropicBackend(apiKey: "").respond(to: ModelRequest(instructions: "", messages: [], tools: []), tools: gate)
        }
    }
}
