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
                .tint(.kithMoss)
                .navigationTitle("Kith")
                .navigationSubtitle(model.settings.privacy.title)
                .frame(minWidth: 480, minHeight: 520)
                .containerBackground(Color.kithPaper, for: .window)
                .toolbarBackground(Color.kithPaper, for: .windowToolbar)
                .task {
                    await model.start()
                    #if DEBUG
                        await DemoCapture.runIfRequested(model: model)
                    #endif
                }
        }
        .defaultSize(width: 680, height: 800)

        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
                .task { await model.start() }
        } label: {
            // The mark as a template image; a count appears beside it when something waits for you.
            if model.pending.isEmpty {
                Image("MenuBarMark")
            } else {
                HStack(spacing: 3) {
                    Image("MenuBarMark")
                    Text("\(model.pending.count)")
                }
            }
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
                KithMark(size: 22)
                Text("Kith").font(.kithDisplay(15)).foregroundStyle(Color.kithInk)
                Spacer()
                Text(model.settings.privacy.title).font(.caption.weight(.medium)).foregroundStyle(Color.kithMuted)
            }
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
        .background(Color.kithPaper)
        .tint(.kithMoss)
    }
}
