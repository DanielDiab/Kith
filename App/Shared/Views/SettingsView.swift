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
        #if os(macOS)
            TabView {
                Form { privacySection; dataSection }
                    .formStyle(.grouped)
                    .tabItem { Label("General", systemImage: "gearshape") }
                Form { modelsSection; localModelSection; claudeSection }
                    .formStyle(.grouped)
                    .tabItem { Label("Models", systemImage: "cpu") }
                Form { toolsSection }
                    .formStyle(.grouped)
                    .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                Form { MCPSection() }
                    .formStyle(.grouped)
                    .tabItem { Label("MCP", systemImage: "point.3.connected.trianglepath.dotted") }
            }
            .frame(width: 560, height: 560)
            .task { await model.refresh() }
        #else
            Form {
                privacySection
                dataSection
                modelsSection
                localModelSection
                claudeSection
                toolsSection
            }
            .formStyle(.grouped)
            .task { await model.refresh() }
        #endif
    }

    private func update(_ change: (inout KithSettings) -> Void) {
        var s = model.settings
        change(&s)
        Task { await model.apply(s) }
    }

    // MARK: Sections

    private var privacySection: some View {
        Section {
            ForEach([PrivacyMode.deviceOnly, .ownHardware, .allowCloud], id: \.self) { mode in
                PrivacyOptionRow(mode: mode, selected: model.settings.privacy == mode) {
                    update { $0.privacy = mode }
                }
            }
        } header: {
            Text("Where answers may run")
        } footer: {
            Text("The router decides in code before any model runs, and writes its reasons into every answer's details.")
        }
    }

    private var dataSection: some View {
        Section {
            Picker("Source", selection: Binding(get: { model.settings.dataSource }, set: { v in update { $0.dataSource = v } })) {
                Text("Demo week").tag(KithSettings.DataSource.demo)
                Text("My Calendar, Reminders and Contacts").tag(KithSettings.DataSource.apple)
            }
            if model.settings.dataSource == .demo {
                Toggle(isOn: Binding(get: { model.settings.plantPoisonedInvite }, set: { v in update { $0.plantPoisonedInvite = v } })) {
                    Text("Plant a poisoned invite")
                    Text("Adds an event whose title tries to instruct the assistant, to see the data guard withhold it.")
                }
            }
            if model.settings.dataSource == .apple {
                LabeledContent("Access") {
                    Button("Grant Access…") {
                        Task {
                            let a = await model.requestAppleAccess()
                            accessMessage = "Calendar \(a.calendar ? "✓" : "✗")  Reminders \(a.reminders ? "✓" : "✗")  Contacts \(a.contacts ? "✓" : "✗")"
                        }
                    }
                }
                if let accessMessage { Text(accessMessage).font(.callout).foregroundStyle(.secondary) }
            }
        } header: {
            Text("Data")
        } footer: {
            Text(model.settings.dataSource == .demo
                 ? "A made-up week frozen at Wednesday 4 November, 08:00. Safe for demos and screenshots."
                 : "Kith reads your data on this device. Changes always wait for your confirmation.")
        }
    }

    private var modelsSection: some View {
        Section {
            ForEach(model.profiles, id: \.tier) { p in
                LabeledContent {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(p.available ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text(p.available ? p.model : (p.unavailableReason ?? "Unavailable"))
                            .foregroundStyle(p.available ? .primary : .secondary)
                    }
                    .font(.callout)
                } label: {
                    Label(p.tier.label, systemImage: p.tier.symbol)
                }
            }
        } header: {
            Text("Models")
        } footer: {
            Text("Simple questions go to the cheapest model that fits; a failed check moves the question up one tier.")
        }
    }

    private var localModelSection: some View {
        Section {
            Toggle("Use an open model on my Mac", isOn: Binding(get: { model.settings.useLocalModel }, set: { v in update { $0.useLocalModel = v } }))
            if model.settings.useLocalModel {
                TextField("Endpoint", text: Binding(get: { model.settings.localModelURL }, set: { v in update { $0.localModelURL = v } }))
                TextField("Model", text: Binding(get: { model.settings.localModel }, set: { v in update { $0.localModel = v } }))
            }
        } header: {
            Text("Your Mac")
        } footer: {
            Text("Any OpenAI-compatible server works. With Ollama: ollama pull qwen3:8b")
        }
    }

    private var claudeSection: some View {
        Section {
            if model.claudeKeySet {
                LabeledContent("API key") {
                    HStack {
                        Label("Saved in Keychain", systemImage: "key.fill").foregroundStyle(.secondary)
                        Button("Remove", role: .destructive) { Task { await model.setClaudeKey("") } }
                    }
                }
            } else {
                SecureField("API key", text: $claudeKey, prompt: Text("sk-ant-…"))
                    .onSubmit { Task { await model.setClaudeKey(claudeKey); claudeKey = "" } }
            }
        } header: {
            Text("Claude")
        } footer: {
            Text("Optional. Used only when “Allow Claude” is on and nothing local fits.")
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

/// One privacy mode: what it's called, what it means, and a checkmark when it's the one in use.
struct PrivacyOptionRow: View {
    let mode: PrivacyMode
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title).foregroundStyle(.primary)
                    Text(mode.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
