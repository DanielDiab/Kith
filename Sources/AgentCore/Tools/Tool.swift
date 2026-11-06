import Foundation

/// Whether a tool only reads the user's data or changes it. The effect is declared in
/// the tool catalog, not by whoever enables the tool: every `.write` is held for the
/// user's confirmation, and no permission setting can turn that off.
public enum ToolEffect: String, Codable, Sendable {
    case read
    case write
}

public struct ToolParameter: Codable, Sendable, Equatable {
    public var name: String
    /// "string", "integer", "boolean", or "date-time" (ISO 8601 with offset).
    public var type: String
    public var description: String
    public var required: Bool

    public init(_ name: String, type: String, description: String, required: Bool = true) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
    }
}

public struct ToolSpec: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var description: String
    public var effect: ToolEffect
    public var parameters: [ToolParameter]

    public var id: String { name }

    public init(name: String, description: String, effect: ToolEffect, parameters: [ToolParameter] = []) {
        self.name = name
        self.description = description
        self.effect = effect
        self.parameters = parameters
    }

    /// JSON Schema for the arguments, in the shape MCP `tools/list` expects.
    public var inputSchema: JSONValue {
        var properties: [String: JSONValue] = [:]
        for p in parameters {
            var prop: [String: JSONValue] = ["description": .string(p.description)]
            switch p.type {
            case "integer": prop["type"] = "integer"
            case "boolean": prop["type"] = "boolean"
            case "date-time":
                prop["type"] = "string"
                prop["format"] = "date-time"
            default: prop["type"] = "string"
            }
            properties[p.name] = .object(prop)
        }
        return [
            "type": "object",
            "properties": .object(properties),
            "required": .array(parameters.filter(\.required).map { .string($0.name) }),
        ]
    }

    /// Returns the names of required arguments that are missing.
    public func missingArguments(in arguments: JSONValue) -> [String] {
        parameters.filter { p in
            guard p.required else { return false }
            switch arguments[p.name] {
            case nil, .null?: return true
            case .string(let s)?: return s.trimmingCharacters(in: .whitespaces).isEmpty
            default: return false
            }
        }.map(\.name)
    }
}

public enum ToolError: Error, Equatable, Sendable {
    case invalidArguments(String)
    case notFound(String)
    case permissionDenied(String)
    case backend(String)

    public var message: String {
        switch self {
        case .invalidArguments(let m), .notFound(let m), .permissionDenied(let m), .backend(let m): return m
        }
    }
}

/// A tool the agent can call. Implementations live next to the data they reach
/// (`PersonalData` for the fakes, the EventKit adapter in the app).
public protocol ToolHandler: Sendable {
    var spec: ToolSpec { get }
    func call(_ arguments: JSONValue) async throws -> JSONValue
    /// One line a person reads before confirming a write ("Create “Dentist” on Wed 4 Nov, 10:00–10:45").
    func preview(_ arguments: JSONValue) async -> String
    /// Turns a write's arguments into the exact ones that will run, before it is held: a
    /// reminder named by title becomes its id, so what the person confirms can't change later.
    /// `personSaid` is the person's message inside the agent, empty for MCP clients, whose
    /// arguments are already explicit; a write can check its arguments against it. Throws
    /// `ToolError` when the arguments don't name exactly one thing or contradict the message.
    func resolve(_ arguments: JSONValue, personSaid: String) async throws -> JSONValue
}

extension ToolHandler {
    public func resolve(_ arguments: JSONValue, personSaid: String) async throws -> JSONValue { arguments }

    public func preview(_ arguments: JSONValue) async -> String {
        "\(spec.name) \(arguments.jsonString())"
    }
}

public struct ToolRegistry: Sendable {
    private let handlers: [String: any ToolHandler]
    public let specs: [ToolSpec]

    public init(_ handlers: [any ToolHandler]) {
        var byName: [String: any ToolHandler] = [:]
        for h in handlers { byName[h.spec.name] = h }
        self.handlers = byName
        self.specs = handlers.map(\.spec)
    }

    public func handler(named name: String) -> (any ToolHandler)? { handlers[name] }

    public func spec(named name: String) -> ToolSpec? { handlers[name]?.spec }
}
