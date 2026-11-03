import Foundation

/// Who is asking. The app (and Siri through App Intents) is the person at the device;
/// an MCP client is another agent acting on their behalf, so it gets its own grants.
public enum Client: Hashable, Sendable, Codable, CustomStringConvertible {
    case app
    case siri
    case mcp(String)

    public var description: String {
        switch self {
        case .app: return "app"
        case .siri: return "siri"
        case .mcp(let name): return "mcp:\(name)"
        }
    }

    public init(label: String) {
        switch label {
        case "app": self = .app
        case "siri": self = .siri
        default: self = .mcp(label.hasPrefix("mcp:") ? String(label.dropFirst(4)) : label)
        }
    }
}

public enum ClientScope: Codable, Sendable, Equatable {
    /// The app, Siri and every MCP client.
    case everyone
    /// The app and Siri only: no MCP client sees this tool.
    case onDevice
    /// The app, Siri and the named MCP clients.
    case mcpClients([String])

    public func allows(_ client: Client) -> Bool {
        switch (self, client) {
        case (.everyone, _), (_, .app), (_, .siri): return true
        case (.onDevice, .mcp): return false
        case (.mcpClients(let names), .mcp(let name)): return names.contains(name)
        }
    }
}

public struct ToolGrant: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var scope: ClientScope

    public init(enabled: Bool = true, scope: ClientScope = .everyone) {
        self.enabled = enabled
        self.scope = scope
    }
}

public enum PermissionDecision: Equatable, Sendable {
    case allow
    case holdForConfirmation
    case deny(String)
}

/// Explicit, per-tool permissions. A tool without a grant is denied: the person turns
/// each tool on, and decides whether MCP clients may use it.
public struct PermissionPolicy: Codable, Sendable, Equatable {
    public var grants: [String: ToolGrant]

    public init(grants: [String: ToolGrant] = [:]) {
        self.grants = grants
    }

    public func decide(_ spec: ToolSpec, for client: Client) -> PermissionDecision {
        guard let grant = grants[spec.name], grant.enabled else {
            return .deny("The tool \(spec.name) is turned off in the app's permissions.")
        }
        guard grant.scope.allows(client) else {
            return .deny("The tool \(spec.name) is not shared with \(client).")
        }
        // Writes are held whatever the grant says. This is the catalog's rule, not a setting.
        return spec.effect == .write ? .holdForConfirmation : .allow
    }

    /// Every tool on, shared with everyone. Convenient for tests and first launch on a dev machine.
    public static func allowAll(_ specs: [ToolSpec]) -> PermissionPolicy {
        PermissionPolicy(grants: Dictionary(uniqueKeysWithValues: specs.map { ($0.name, ToolGrant()) }))
    }
}
