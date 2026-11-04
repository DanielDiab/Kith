import AgentCore
import Foundation
import MCP

extension JSONValue {
    /// Converts an MCP SDK value into the agent's JSON value.
    public init(mcp value: MCP.Value) {
        switch value {
        case .null: self = .null
        case .bool(let b): self = .bool(b)
        case .int(let i): self = .number(Double(i))
        case .double(let d): self = .number(d)
        case .string(let s): self = .string(s)
        case .data(_, let d): self = .string(d.base64EncodedString())
        case .array(let a): self = .array(a.map { JSONValue(mcp: $0) })
        case .object(let o): self = .object(o.mapValues { JSONValue(mcp: $0) })
        }
    }

    /// Converts the agent's JSON value into an MCP SDK value.
    public var mcpValue: MCP.Value {
        switch self {
        case .null: return MCP.Value.null
        case .bool(let b): return .bool(b)
        case .number(let n): return n.rounded() == n && abs(n) < 1e15 ? MCP.Value.int(Int(n)) : MCP.Value.double(n)
        case .string(let s): return .string(s)
        case .array(let a): return .array(a.map(\.mcpValue))
        case .object(let o): return .object(o.mapValues(\.mcpValue))
        }
    }
}
