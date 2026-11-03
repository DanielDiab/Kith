import Foundation

public struct ModelRequest: Sendable {
    public var instructions: String
    public var messages: [ChatMessage]
    public var tools: [ToolSpec]

    public init(instructions: String, messages: [ChatMessage], tools: [ToolSpec]) {
        self.instructions = instructions
        self.messages = messages
        self.tools = tools
    }
}

public struct ModelReply: Sendable, Equatable {
    public var text: String
    public var usage: TokenUsage

    public init(text: String, usage: TokenUsage) {
        self.text = text
        self.usage = usage
    }
}

public enum BackendError: Error, Equatable, Sendable {
    case unavailable(String)
    case contextExceeded
    case rateLimited
    case failed(String)
}

/// A model the agent can run on. A backend runs its own tool loop, the way a Foundation
/// Models `LanguageModelSession` does, but every tool call goes through the `ToolGate`.
/// The gate is the only path to the person's data, so permissions, held writes and the data
/// guard apply the same way whichever model is driving.
public protocol LanguageBackend: Sendable {
    var tier: Tier { get }
    var modelName: String { get }
    func respond(to request: ModelRequest, tools: ToolGate) async throws -> ModelReply
}

/// A backend that follows a script. It stands in for the model in tests and in the
/// no-model eval suites. In the red-team suites the script plays a fully compromised
/// model, one that obeys whatever instruction it reads in the data, so the suite measures
/// what the platform stops on its own.
public actor ScriptedBackend: LanguageBackend {
    public struct Step: Codable, Sendable, Equatable {
        public var call: String?
        public var args: JSONValue?
        public var answer: String?

        public init(call: String, args: JSONValue = [:]) {
            self.call = call
            self.args = args
        }

        public init(answer: String) {
            self.answer = answer
        }
    }

    public nonisolated let tier: Tier
    public nonisolated let modelName: String
    private let attempts: [[Step]]
    private var attempt = 0
    private var callCounter = 0
    public private(set) var requests: [ModelRequest] = []

    /// Each call to `respond` plays the next attempt; the last one repeats if the agent asks again.
    public init(tier: Tier = .onDevice, modelName: String = "scripted", attempts: [[Step]]) {
        self.tier = tier
        self.modelName = modelName
        self.attempts = attempts
    }

    public init(tier: Tier = .onDevice, modelName: String = "scripted", steps: [Step]) {
        self.tier = tier
        self.modelName = modelName
        self.attempts = [steps]
    }

    public func respond(to request: ModelRequest, tools: ToolGate) async throws -> ModelReply {
        requests.append(request)
        let steps = attempts.isEmpty ? [] : attempts[min(attempt, attempts.count - 1)]
        attempt += 1
        var seen = request.instructions + request.messages.map(\.content).joined()
        for step in steps {
            if let name = step.call {
                callCounter += 1
                let result = await tools.execute(ToolCall(id: "c\(callCounter)", name: name, arguments: step.args ?? [:]))
                seen += result.jsonString()
            } else if let answer = step.answer {
                return ModelReply(text: answer, usage: .estimate(input: seen, output: answer))
            }
        }
        return ModelReply(text: "", usage: .estimate(input: seen, output: ""))
    }

    public func requestCount() -> Int { requests.count }
}
