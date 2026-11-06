import AgentCore
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Claude through the Messages API: the `claude` tier, used only when the person's privacy
/// mode allows cloud and nothing local fits. The tool loop runs here, so every tool call
/// still goes through the gate on the device; Claude sees only gated, sanitized results.
///
/// This talks to the API directly instead of through Anthropic's ClaudeForFoundationModels
/// package (beta, OS 27 only). Keeping it in plain Foundation lets CI test the tool loop on
/// Linux, and the app can switch to the package later behind the same `LanguageBackend`.
public struct AnthropicBackend: LanguageBackend {
    public let tier = Tier.claude
    public let modelName: String
    public let contextTokens: Int
    let apiKey: String
    let baseURL: URL
    let client: any HTTPClient
    let maxTokens: Int
    let maxRounds: Int

    public init(
        apiKey: String, model: String = "claude-sonnet-5-5", contextTokens: Int = 200_000,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!, client: any HTTPClient = URLSessionHTTPClient(),
        maxTokens: Int = 1_024, maxRounds: Int = 6
    ) {
        self.apiKey = apiKey
        self.modelName = model
        self.contextTokens = contextTokens
        self.baseURL = baseURL
        self.client = client
        self.maxTokens = maxTokens
        self.maxRounds = maxRounds
    }

    public func profile() -> TierProfile {
        TierProfile(
            tier: .claude, model: modelName, contextTokens: contextTokens, available: !apiKey.isEmpty,
            unavailableReason: apiKey.isEmpty ? "no Claude API key in Settings" : nil)
    }

    public func respond(to request: ModelRequest, tools: ToolGate) async throws -> ModelReply {
        guard !apiKey.isEmpty else { throw BackendError.unavailable("no Claude API key") }
        var messages: [JSONValue] = request.messages.map { m in
            ["role": .string(m.role == .assistant ? "assistant" : "user"), "content": .string(m.content)]
        }
        let toolList: [JSONValue] = request.tools.map { spec in
            ["name": .string(spec.name), "description": .string(spec.description), "input_schema": spec.inputSchema]
        }
        let headers = ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
        var usage = TokenUsage.zero

        // No forced `tool_choice`: Claude Sonnet 5.5 and Opus 5.5 reject `any`/`tool` with a
        // 400. The instructions and the agent's completeness check do the steering instead.
        for _ in 0..<maxRounds {
            var body: [String: JSONValue] = [
                "model": .string(modelName), "max_tokens": .number(Double(maxTokens)),
                "system": .string(request.instructions), "messages": .array(messages),
            ]
            if !toolList.isEmpty { body["tools"] = .array(toolList) }
            let response = try await HTTP.post(
                baseURL.appendingPathComponent("messages"), json: .object(body), headers: headers, client: client, timeout: 120)
            usage = usage + Self.usage(response["usage"])
            let blocks = response["content"]?.arrayValue ?? []
            let toolUses = blocks.filter { $0["type"]?.stringValue == "tool_use" }
            if toolUses.isEmpty || response["stop_reason"]?.stringValue != "tool_use" {
                let text = blocks.compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }.joined()
                return ModelReply(text: text.trimmingCharacters(in: .whitespacesAndNewlines), usage: usage)
            }
            messages.append(["role": "assistant", "content": .array(blocks)])
            var results: [JSONValue] = []
            for use in toolUses {
                let id = use["id"]?.stringValue ?? ""
                let output = await tools.execute(
                    ToolCall(id: id, name: use["name"]?.stringValue ?? "", arguments: use["input"] ?? [:]))
                results.append(["type": "tool_result", "tool_use_id": .string(id), "content": .string(output.jsonString())])
            }
            messages.append(["role": "user", "content": .array(results)])
        }
        throw BackendError.failed("no answer after \(maxRounds) tool rounds")
    }

    static func usage(_ u: JSONValue?) -> TokenUsage {
        guard let u else { return .zero }
        let cached = u["cache_read_input_tokens"]?.intValue ?? 0
        return TokenUsage(input: (u["input_tokens"]?.intValue ?? 0) + cached, cachedInput: cached, output: u["output_tokens"]?.intValue ?? 0)
    }
}
