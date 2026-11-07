import AgentCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

@main
struct KithMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Kith", id: "main") {
            ChatView()
                .environment(model)
                .frame(minWidth: 520, minHeight: 560)
                .task { await model.start() }
        }
        .defaultSize(width: 640, height: 760)

        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
                .task { await model.start() }
        } label: {
            Image(systemName: model.pending.isEmpty ? "bubble.left.and.text.bubble.right" : "bubble.left.and.exclamationmark.bubble.right")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 560, height: 640)
        }
    }
}

/// The menu bar: a quick question, the last answer with its trace badge, and anything waiting
/// for confirmation (including writes proposed by an MCP client).
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var draft = ""
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ask Kith", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let text = draft
                    draft = ""
                    Task { await model.send(text) }
                }
            if model.busy { ProgressView().controlSize(.small) }
            if let last = model.items.last(where: { !$0.fromPerson }) {
                Text(Format.markdown(last.text)).lineLimit(6).textSelection(.enabled)
                if let turn = last.turn { TurnBadge(turn: turn, expanded: $expanded) }
                if expanded, let turn = last.turn { ScrollView { TraceView(trace: turn.trace) }.frame(maxHeight: 260) }
            }
            if !model.pending.isEmpty {
                Divider()
                ScrollView { PendingWritesView() }.frame(maxHeight: 280)
            }
            Divider()
            HStack {
                Button("Open Kith") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                SettingsLink { Text("Settings…") }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 360)
    }
}
