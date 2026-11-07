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
                .navigationTitle("Kith")
                .navigationSubtitle(model.settings.privacy.title)
                .frame(minWidth: 480, minHeight: 520)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Ask Kith", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let text = draft
                        draft = ""
                        Task { await model.send(text) }
                    }
                PrivacyMenu()
            }
            if model.busy { ThinkingRow() }
            if let last = model.items.last(where: { !$0.fromPerson && $0.notice == nil }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Format.markdown(last.text)).textSelection(.enabled)
                        if let turn = last.turn {
                            AnswerFooter(turn: turn, expanded: $expanded)
                            if expanded { TraceView(trace: turn.trace) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: expanded ? 420 : 220)
            }
            if !model.pending.isEmpty {
                ScrollView { PendingWritesView() }.frame(maxHeight: 300)
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
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 380)
    }
}
