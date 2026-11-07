import AgentCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var claudeKey = ""
    @State private var accessMessage: String?

    var body: some View {
        Form {
            dataSection
            privacySection
            modelsSection
            toolsSection
            #if os(macOS)
                MCPSection()
            #endif
        }
        .formStyle(.grouped)
        .task { await model.refresh() }
    }

    private func update(_ change: (inout KithSettings) -> Void) {
        var s = model.settings
        change(&s)
        Task { await model.apply(s) }
    }

    private var dataSection: some View {
        Section("Data") {
            Picker("Source", selection: Binding(get: { model.settings.dataSource }, set: { v in update { $0.dataSource = v } })) {
                Text("Demo week (synthetic)").tag(KithSettings.DataSource.demo)
                Text("My Calendar, Reminders and Contacts").tag(KithSettings.DataSource.apple)
            }
            if model.settings.dataSource == .demo {
                Toggle("Plant a poisoned invite (shows the data guard)", isOn: Binding(
                    get: { model.settings.plantPoisonedInvite }, set: { v in update { $0.plantPoisonedInvite = v } }))
            }
            if model.settings.dataSource == .apple {
                Button("Grant access") {
                    Task {
                        let a = await model.requestAppleAccess()
                        accessMessage = "Calendar \(a.calendar ? "✓" : "✗") · Reminders \(a.reminders ? "✓" : "✗") · Contacts \(a.contacts ? "✓" : "✗")"
                    }
                }
                if let accessMessage { Text(accessMessage).font(.caption) }
            }
        }
    }

    private var privacySection: some View {
        Section {
            Picker("Where answers may run", selection: Binding(get: { model.settings.privacy }, set: { v in update { $0.privacy = v } })) {
                Text("This device only").tag(PrivacyMode.deviceOnly)
                Text("My own hardware (device + Mac)").tag(PrivacyMode.ownHardware)
                Text("Allow Claude when needed").tag(PrivacyMode.allowCloud)
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("The router decides in code before any model runs. Claude is only used when this allows it and nothing local fits.")
        }
    }

    private var modelsSection: some View {
        Section("Models") {
            ForEach(model.profiles, id: \.tier) { p in
                HStack {
                    Label(p.tier.label, systemImage: p.tier.symbol)
                    Spacer()
                    Text(p.available ? p.model : (p.unavailableReason ?? "unavailable"))
                        .font(.caption)
                        .foregroundStyle(p.available ? .green : .secondary)
                }
            }
            Toggle("Use an open model on my Mac (Ollama)", isOn: Binding(get: { model.settings.useLocalModel }, set: { v in update { $0.useLocalModel = v } }))
            TextField("Endpoint", text: Binding(get: { model.settings.localModelURL }, set: { v in update { $0.localModelURL = v } }))
            TextField("Model", text: Binding(get: { model.settings.localModel }, set: { v in update { $0.localModel = v } }))
            SecureField(model.claudeKeySet ? "Claude API key (saved in Keychain)" : "Claude API key (optional)", text: $claudeKey)
                .onSubmit { Task { await model.setClaudeKey(claudeKey); claudeKey = "" } }
            if model.claudeKeySet {
                Button("Remove Claude key", role: .destructive) { Task { await model.setClaudeKey("") } }
            }
        }
    }

    private var toolsSection: some View {
        Section {
            ForEach(model.specs) { spec in
                ToolGrantRow(spec: spec)
            }
        } header: {
            Text("Tools")
        } footer: {
            Text("Writes are always held for your confirmation, whoever proposes them. “This device only” hides a tool from MCP clients.")
        }
    }
}

struct ToolGrantRow: View {
    @Environment(AppModel.self) private var model
    let spec: ToolSpec

    private var grant: ToolGrant { model.settings.grants[spec.name] ?? ToolGrant() }

    private func set(_ g: ToolGrant) {
        var s = model.settings
        s.grants[spec.name] = g
        Task { await model.apply(s) }
    }

    var body: some View {
        // Name on the left; scope and switch in fixed columns so every row lines up.
        HStack {
            VStack(alignment: .leading) {
                Text(spec.name).font(.body.monospaced())
                Text(spec.effect == .write ? "write · held for confirmation" : "read").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker(spec.name, selection: Binding(
                get: { grant.scope == .onDevice ? 1 : 0 },
                set: { v in var g = grant; g.scope = v == 1 ? .onDevice : .everyone; set(g) }
            )) {
                Text("Everyone").tag(0)
                Text("This device only").tag(1)
            }
            .labelsHidden()
            .fixedSize()
            .frame(width: 170, alignment: .trailing)
            Toggle(spec.name, isOn: Binding(get: { grant.enabled }, set: { v in var g = grant; g.enabled = v; set(g) }))
                .labelsHidden()
        }
    }
}

#if os(macOS)
    struct MCPSection: View {
        @Environment(AppModel.self) private var model
        @State private var path = ""

        private var config: String {
            """
            {
              "mcpServers": {
                "kith": { "command": "/path/to/Kith/.build/release/kith-mcp" }
              }
            }
            """
        }

        var body: some View {
            Section {
                Toggle("Serve my data to MCP clients", isOn: Binding(
                    get: { model.settings.mcpEnabled },
                    set: { v in var s = model.settings; s.mcpEnabled = v; Task { await model.apply(s) } }))
                if model.settings.mcpEnabled {
                    LabeledContent("Socket", value: path)
                    Text("Build the relay with `swift build -c release --product kith-mcp`, then add it to Claude Desktop:")
                        .font(.caption)
                    Text(config).font(.caption.monospaced()).textSelection(.enabled)
                    Button("Copy config") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(config, forType: .string)
                    }
                    if !model.mcpActivity.isEmpty {
                        ForEach(model.mcpActivity.prefix(8), id: \.id) { trace in
                            HStack {
                                Text(trace.client.label).font(.caption)
                                Text(trace.userText).font(.caption.monospaced()).lineLimit(1)
                                Spacer()
                                Text(trace.spans.last?.status.rawValue ?? "").font(.caption2)
                            }
                        }
                    }
                }
            } header: {
                Text("MCP")
            } footer: {
                Text("Claude Desktop or Claude Code get the same tools through the same gate. They can propose changes; only you confirm them, here.")
            }
            .task { path = await KithRuntime.shared.mcpSocketPath }
        }
    }
#endif
