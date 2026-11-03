import Foundation

/// A JSON value. Tool arguments and tool results travel as `JSONValue` so the guards
/// can walk them field by field: the data guard scans every string leaf for planted
/// instructions, and the output guard collects every number, date and name as evidence.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    public var intValue: Int? {
        if case .number(let n) = self, n.rounded() == n { return Int(n) }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Compact JSON with sorted keys, so traces and tests are deterministic.
    public func jsonString(pretty: Bool = false) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { try container.encode(Int64(n)) } else { try container.encode(n) }
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    /// Every leaf with the key path that leads to it ("events[0].title").
    public func leaves(prefix: String = "") -> [(path: String, value: JSONValue)] {
        switch self {
        case .object(let fields):
            return fields.keys.sorted().flatMap { key in
                fields[key]!.leaves(prefix: prefix.isEmpty ? key : "\(prefix).\(key)")
            }
        case .array(let items):
            return items.enumerated().flatMap { index, item in item.leaves(prefix: "\(prefix)[\(index)]") }
        default:
            return [(prefix, self)]
        }
    }

    /// Returns a copy with every string leaf passed through `transform`.
    public func mapStrings(_ transform: (_ path: String, _ value: String) -> String, prefix: String = "") -> JSONValue {
        switch self {
        case .string(let s):
            return .string(transform(prefix, s))
        case .object(let fields):
            var out: [String: JSONValue] = [:]
            for (key, value) in fields {
                out[key] = value.mapStrings(transform, prefix: prefix.isEmpty ? key : "\(prefix).\(key)")
            }
            return .object(out)
        case .array(let items):
            return .array(items.enumerated().map { index, item in item.mapStrings(transform, prefix: "\(prefix)[\(index)]") })
        default:
            return self
        }
    }
}
