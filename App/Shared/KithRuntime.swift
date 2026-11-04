import AgentCore
import AppleData
import Foundation
import ModelBackends
import PersonalData

#if os(macOS)
    import KithMCP
#endif

/// What the person chose in Settings. Stored in UserDefaults; the Claude key lives in the Keychain.
struct KithSettings: Codable, Equatable, Sendable {
    enum DataSource: String, Codable, CaseIterable, Sendable {
        /// The synthetic week from `SyntheticData`: safe for demos and screenshots.
        case demo
        /// The person's own Calendar, Reminders and Contacts.
        case apple
    }

    var dataSource: DataSource = .demo
    var privacy: PrivacyMode = .ownHardware
    var useLocalModel = true
    var localModelURL = "http://localhost:11434/v1"
    var localModel = "qwen3:8b"
    var claudeModel = "claude-sonnet-5-5"
    var mcpEnabled = false
    /// Demo only: add an invite whose title tries to instruct the assistant.
    var plantPoisonedInvite = false
    /// Overrides per tool. A tool without an entry is on and shared with everyone.
    var grants: [String: ToolGrant] = [:]

    func policy(for specs: [ToolSpec]) -> PermissionPolicy {
        var all: [String: ToolGrant] = [:]
        for spec in specs { all[spec.name] = grants[spec.name] ?? ToolGrant() }
        return PermissionPolicy(grants: all)
    }

    static let key = "kith.settings"

    static func load() -> KithSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(KithSettings.self, from: data) else { return KithSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// One runtime per process, shared by the UI, App Intents and the MCP host, so all three see
/// the same pending writes and the same trace log.
actor KithRuntime {
    static let shared = KithRuntime()
    static let claudeKeyAccount = "claude-api-key"

    let pending = PendingWriteStore()
    let traces = TraceLog()
    private(set) var settings = KithSettings.load()
    private var store: any PersonalDataStore = SyntheticData.store()
    private var registry = ToolRegistry([])
    private var agent: Agent?
    private var configured = false
    private(set) var profiles: [TierProfile] = []
    #if os(macOS)
        private var host: SocketHost?
    #endif

    var timeZone: TimeZone { settings.dataSource == .demo ? SyntheticData.timeZone : .current }
    var specs: [ToolSpec] { registry.specs }

    func configure(_ new: KithSettings) async {
        let sourceChanged = !configured || new.dataSource != settings.dataSource
            || new.plantPoisonedInvite != settings.plantPoisonedInvite
        settings = new
        new.save()
        if sourceChanged {
            store = new.dataSource == .demo ? SyntheticData.store(withPoisonedInvite: new.plantPoisonedInvite) : EventKitStore()
            registry = ToolRegistry(PersonalTools.all(store: store, format: LocalFormat(timeZone: timeZone)))
        }
        configured = true
        agent = nil
        await refreshProfiles()
        #if os(macOS)
            await updateMCP(restart: sourceChanged)
        #endif
    }

    func ensureConfigured() async {
        if !configured { await configure(settings) }
    }

    func policy() -> PermissionPolicy { settings.policy(for: registry.specs) }

    // MARK: Models

    private func backends() -> [any LanguageBackend] {
        var list: [any LanguageBackend] = []
        if #available(macOS 26.0, iOS 26.0, *) { list.append(OnDeviceBackend()) }
        if settings.useLocalModel, let url = URL(string: settings.localModelURL) {
            list.append(ChatCompletionsBackend(model: settings.localModel, baseURL: url))
        }
        if let key = Keychain.read(Self.claudeKeyAccount), !key.isEmpty {
            list.append(AnthropicBackend(apiKey: key, model: settings.claudeModel))
        }
        return list
    }

    func refreshProfiles() async {
        var result: [TierProfile] = []
        if #available(macOS 26.0, iOS 26.0, *) {
            result.append(OnDeviceBackend.profile())
        } else {
            result.append(TierProfile(tier: .onDevice, model: "apple-on-device", contextTokens: 4_096, available: false,
                                      unavailableReason: "needs macOS 26 or iOS 26"))
        }
        if settings.useLocalModel, let url = URL(string: settings.localModelURL) {
            result.append(await ChatCompletionsBackend(model: settings.localModel, baseURL: url).profile())
        } else {
            result.append(TierProfile(tier: .localOpen, model: settings.localModel, contextTokens: 32_768, available: false,
                                      unavailableReason: "turned off in Settings"))
        }
        let key = Keychain.read(Self.claudeKeyAccount) ?? ""
        result.append(AnthropicBackend(apiKey: key, model: settings.claudeModel).profile())
        profiles = result
    }

    private func currentAgent() async -> Agent {
        await ensureConfigured()
        if let agent { return agent }
        let names = (try? await store.allContactNames()) ?? []
        // The demo week is frozen at Wednesday 4 Nov 2026, 08:00, so "today" means the same thing in every demo.
        let fixed = SyntheticData.now
        let clock: @Sendable () -> Date
        if settings.dataSource == .demo { clock = { fixed } } else { clock = { Date() } }
        let config = AgentConfig(timeZone: timeZone, privacy: settings.privacy)
        let router = Router(profiles: profiles)
        let built = Agent(
            config: config, router: router, backends: backends(), registry: registry, policy: policy(),
            pending: pending, knownNames: names, now: clock)
        agent = built
        return built
    }

    // MARK: Turns

    func respond(to text: String, client: Client, history: [ChatMessage]) async -> AgentTurn {
        let turn = await currentAgent().respond(to: text, client: client, history: history)
        await traces.append(turn.trace)
        return turn
    }

    func confirm(_ id: String) async throws -> ConfirmationResult {
        let result = try await currentAgent().confirm(id)
        await traces.append(result.trace)
        return result
    }

    func reject(_ id: String) async throws {
        try await pending.reject(id)
    }

    func pendingWrites() async -> [PendingWrite] {
        await pending.all()
    }

    /// Runs one read tool without a model, for App Intents that answer instantly. It still goes
    /// through the gate as `.siri`, so grants, the data guard and the trace apply.
    func read(_ tool: String, _ arguments: JSONValue) async throws -> JSONValue {
        await ensureConfigured()
        guard registry.spec(named: tool)?.effect == .read else { throw ToolError.notFound(tool) }
        let recorder = TraceRecorder(masker: PIIMasker(), prices: .claude2026)
        let gate = ToolGate(
            registry: registry, policy: policy(), client: .siri, pending: pending, recorder: recorder,
            masker: PIIMasker(), userText: "", writeRequested: false)
        let started = Date()
        let result = await gate.execute(ToolCall(id: "intent", name: tool, arguments: arguments))
        await traces.append(Trace(id: "siri-\(UUID().uuidString.prefix(8))", client: .siri, userText: tool,
                                  startedAt: started, spans: await recorder.all()))
        if let message = result["error"]?.stringValue { throw ToolError.permissionDenied(message) }
        return result
    }

    /// For App Intents: the system already asked the person to confirm, so hold and run in one
    /// step. The grant for Siri is checked first, and the write goes through the pending store and
    /// the agent, so it is traced like any other.
    func runConfirmedWrite(_ tool: String, _ arguments: JSONValue, summary: String) async throws -> ConfirmationResult {
        await ensureConfigured()
        guard let spec = registry.spec(named: tool), spec.effect == .write else { throw ToolError.notFound(tool) }
        if case .deny(let reason) = policy().decide(spec, for: .siri) { throw ToolError.permissionDenied(reason) }
        let write = await pending.hold(tool: tool, arguments: arguments, summary: summary, client: .siri, proposedAfterFlaggedData: false)
        return try await confirm(write.id)
    }

    func openReminders() async throws -> [Reminder] {
        await ensureConfigured()
        return try await store.reminders(includeCompleted: false)
    }

    func requestAppleAccess() async -> EventKitStore.Access {
        await EventKitStore().requestAccess()
    }

    // MARK: MCP (macOS)

    #if os(macOS)
        var mcpSocketPath: String { SocketHost.defaultPath }
        var mcpRunning: Bool { host != nil }

        private func updateMCP(restart: Bool) async {
            if !settings.mcpEnabled || restart {
                host?.stop()
                host = nil
            }
            guard settings.mcpEnabled, host == nil else { return }
            let names = (try? await store.allContactNames()) ?? []
            let service = MCPService(
                registry: registry, policy: { await KithRuntime.shared.policy() }, pending: pending, log: traces,
                knownNames: names)
            let newHost = SocketHost(service: service)
            do {
                try newHost.start()
                host = newHost
            } catch {
                host = nil
            }
        }
    #endif
}
