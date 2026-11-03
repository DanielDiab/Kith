import Foundation

public enum Role: String, Codable, Sendable {
    case system, user, assistant, tool
}

public struct ToolCall: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: JSONValue

    public init(id: String, name: String, arguments: JSONValue = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct ChatMessage: Codable, Sendable, Equatable {
    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String) -> ChatMessage { ChatMessage(role: .user, content: text) }
    public static func assistant(_ text: String) -> ChatMessage { ChatMessage(role: .assistant, content: text) }
}

/// Token counts for one model call. Foundation Models reports these on every response
/// (`response.usage`); backends that can't count leave `estimated` set.
public struct TokenUsage: Codable, Sendable, Equatable {
    public var input: Int
    public var cachedInput: Int
    public var output: Int
    public var reasoning: Int
    public var estimated: Bool

    public init(input: Int = 0, cachedInput: Int = 0, output: Int = 0, reasoning: Int = 0, estimated: Bool = false) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.reasoning = reasoning
        self.estimated = estimated
    }

    public static let zero = TokenUsage()

    public var total: Int { input + output + reasoning }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            cachedInput: lhs.cachedInput + rhs.cachedInput,
            output: lhs.output + rhs.output,
            reasoning: lhs.reasoning + rhs.reasoning,
            estimated: lhs.estimated || rhs.estimated
        )
    }

    /// Rough count for backends without a tokenizer: about four characters per token.
    public static func estimate(input: String, output: String) -> TokenUsage {
        TokenUsage(input: max(1, input.count / 4), output: max(1, output.count / 4), estimated: true)
    }
}
