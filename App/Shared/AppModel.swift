import AgentCore
import AppleData
import Foundation
import Observation
import PersonalData

struct ChatItem: Identifiable, Equatable {
    let id = UUID()
    var fromPerson: Bool
    var text: String
    var turn: AgentTurn?
}

/// The UI's view of the runtime. Everything that touches data goes through `KithRuntime`.
@MainActor
@Observable
final class AppModel {
    var settings = KithSettings.load()
    var items: [ChatItem] = []
    var pending: [PendingWrite] = []
    var profiles: [TierProfile] = []
    var specs: [ToolSpec] = []
    var mcpActivity: [Trace] = []
    var busy = false
    var lastError: String?
    var claudeKeySet = (Keychain.read(KithRuntime.claudeKeyAccount) ?? "").isEmpty == false

    private let runtime = KithRuntime.shared
    private var watching = false

    func start() async {
        await runtime.configure(settings)
        await refresh()
        guard !watching else { return }
        watching = true
        let stream = await runtime.traces.updates()
        Task { [weak self] in
            for await trace in stream {
                guard let self else { return }
                if case .mcp = trace.client { self.mcpActivity.insert(trace, at: 0) }
                await self.refresh()
            }
        }
    }

    func refresh() async {
        pending = await runtime.pendingWrites()
        profiles = await runtime.profiles
        specs = await runtime.specs
    }

    func apply(_ new: KithSettings) async {
        settings = new
        await runtime.configure(new)
        await refresh()
    }

    func setClaudeKey(_ key: String) async {
        Keychain.write(key, for: KithRuntime.claudeKeyAccount)
        claudeKeySet = !key.isEmpty
        await apply(settings)
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy else { return }
        let history = items.suffix(6).map { $0.fromPerson ? ChatMessage.user($0.text) : ChatMessage.assistant($0.text) }
        items.append(ChatItem(fromPerson: true, text: trimmed))
        busy = true
        let turn = await runtime.respond(to: trimmed, client: .app, history: Array(history))
        items.append(ChatItem(fromPerson: false, text: turn.reply, turn: turn))
        busy = false
        await refresh()
    }

    func confirm(_ write: PendingWrite) async {
        do {
            _ = try await runtime.confirm(write.id)
            items.append(ChatItem(fromPerson: false, text: "Done: \(write.summary)"))
        } catch {
            lastError = "Couldn't apply “\(write.summary)”: \(error)"
        }
        await refresh()
    }

    func reject(_ write: PendingWrite) async {
        try? await runtime.reject(write.id)
        items.append(ChatItem(fromPerson: false, text: "Discarded: \(write.summary)"))
        await refresh()
    }

    func requestAppleAccess() async -> EventKitStore.Access {
        let access = await runtime.requestAppleAccess()
        await apply(settings)
        return access
    }

    func profile(_ tier: Tier) -> TierProfile? { profiles.first { $0.tier == tier } }
}

extension Tier {
    var label: String {
        switch self {
        case .onDevice: return "On device"
        case .localOpen: return "Your Mac"
        case .claude: return "Claude"
        }
    }

    var symbol: String {
        switch self {
        case .onDevice: return "iphone"
        case .localOpen: return "desktopcomputer"
        case .claude: return "cloud"
        }
    }
}

extension Client {
    var label: String {
        switch self {
        case .app: return "Kith"
        case .siri: return "Siri"
        case .mcp(let name): return "\(name) via MCP"
        }
    }
}

enum Format {
    static func cost(_ usd: Double) -> String {
        usd == 0 ? "$0" : (usd < 0.01 ? String(format: "$%.5f", usd) : String(format: "$%.3f", usd))
    }

    static func ms(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.1f s", value / 1000) : "\(Int(value.rounded())) ms"
    }

    /// Models answer in Markdown; render bold, italics and code, and keep the line breaks.
    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
