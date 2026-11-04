import AgentCore
import SwiftUI

@main
struct KithiOSApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    ChatView().navigationTitle("Kith")
                }
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }

                NavigationStack {
                    PendingTab().navigationTitle("Waiting for you")
                }
                .tabItem { Label("Pending", systemImage: "hourglass") }
                .badge(model.pending.count)

                NavigationStack {
                    SettingsView().navigationTitle("Settings")
                }
                .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .environment(model)
            .task { await model.start() }
        }
    }
}

struct PendingTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if model.pending.isEmpty {
                ContentUnavailableView("Nothing to confirm", systemImage: "checkmark.circle",
                                       description: Text("Changes Kith proposes wait here until you confirm them."))
            } else {
                PendingWritesView().padding()
            }
        }
        .refreshable { await model.refresh() }
    }
}
