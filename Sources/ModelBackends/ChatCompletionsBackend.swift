import AgentCore
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A model behind an OpenAI-compatible `/v1/chat/completions` endpoint. The default is
/// Ollama on the person's own Mac, the `localOpen` tier: a larger open model (Qwen3 8B by
/// default, the model Charter and Aegis settled on) that costs nothing and keeps data on
/// hardware the person owns.
public struct ChatCompletionsBackend: LanguageBackend {
    public let tier: Tier
    public let modelName: String
    public let baseURL: URL
    public let apiKey: String?
    public let contextTokens: Int
    let client: any HTTPClient
    let maxRounds: Int
    let timeout: TimeInterval

    public init(
        model: String = "qwen3:8b", baseURL: URL = URL(string: "http://localhost:11434/v1")!, apiKey: String? = nil,
        tier: Tier = .localOpen, contextTokens: Int = 32_768, client: any HTTPClient = URLSessionHTTPClient(),
        maxRounds: Int = 6, timeout: TimeInterval = 120
    ) {
        self.modelName = model
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.tier = tier
        self.contextTokens = contextTokens
        self.client = client
        self.maxRounds = maxRounds
        self.timeout = timeout
    }

    /// Whether the server answers right now. Ollama not running means the tier is unavailable.
    public func profile() async -> TierProfile {
        let up = await HTTP.get(baseURL.appendingPathComponent("models"), client: client, timeout: 2)
        return TierProfile(
            tier: tier, model: modelName, contextTokens: contextTokens, available: up,
            unavailableReason: up ? nil : "nothing answering at \(baseURL.absoluteString)")
    }

    public func respond(to request: ModelRequest, tools: ToolGate) async throws -> ModelReply {
        var messages: [JSONValue] = [["role": "system", "content": .string(request.instructions)]]
        for m in request.messages {
            messages.append(["role": .string(m.role == .assistant ? "assistant" : "user"), "content": .string(m.content)])
        }
        let toolList: [JSONValue] = request.tools.map { spec in
            ["type": "function", "function": ["name": .string(spec.name), "description": .string(spec.description), "parameters": spec.inputSchema]]
        }
        var usage = TokenUsage.zero
        var headers: [String: String] = [:]
        if let apiKey { headers["authorization"] = "Bearer \(apiKey)" }

        for _ in 0..<maxRounds {
            var body: [String: JSONValue] = ["model": .string(modelName), "messages": .array(messages), "stream": false]
            if !toolList.isEmpty { body["tools"] = .array(toolList) }
            let response = try await HTTP.post(
                baseURL.appendingPathComponent("chat/completions"), json: .object(body), headers: headers, client: client,
                timeout: timeout)
            usage = usage + Self.usage(response["usage"])
            guard let message = response["choices"]?.arrayValue?.first?["message"] else {
                throw BackendError.failed("response has no message")
            }
            let calls = message["tool_calls"]?.arrayValue ?? []
            if calls.isEmpty {
                return ModelReply(text: Self.stripThinking(message["content"]?.stringValue ?? ""), usage: usage)
            }
            messages.append(message)
            for (i, call) in calls.enumerated() {
                let id = call["id"]?.stringValue ?? "call_\(i)"
                let name = call["function"]?["name"]?.stringValue ?? ""
                let args = Self.arguments(call["function"]?["arguments"])
                let result = await tools.execute(ToolCall(id: id, name: name, arguments: args))
                messages.append(["role": "tool", "tool_call_id": .string(id), "content": .string(result.jsonString())])
            }
        }
        throw BackendError.failed("no answer after \(maxRounds) tool rounds")
    }

    /// OpenAI sends arguments as a JSON string; Ollama sometimes sends an object.
    static func arguments(_ raw: JSONValue?) -> JSONValue {
        switch raw {
        case .string(let s)?: return (try? JSONValue.parse(s)) ?? [:]
        case .object?: return raw!
        default: return [:]
        }
    }

    static func usage(_ u: JSONValue?) -> TokenUsage {
        guard let u else { return .zero }
        return TokenUsage(
            input: u["prompt_tokens"]?.intValue ?? 0,
            cachedInput: u["prompt_tokens_details"]?["cached_tokens"]?.intValue ?? 0,
            output: u["completion_tokens"]?.intValue ?? 0,
            reasoning: u["completion_tokens_details"]?["reasoning_tokens"]?.intValue ?? 0)
    }

    /// Qwen3 can emit a `<think>…</think>` block before the answer. It isn't part of the answer.
    static func stripThinking(_ text: String) -> String {
        guard let end = text.range(of: "</think>") else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
