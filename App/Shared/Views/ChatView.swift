import AgentCore
import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if !model.pending.isEmpty {
                PendingWritesView()
                    .padding([.horizontal, .top])
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if model.items.isEmpty { EmptyState() }
                        ForEach(model.items) { item in
                            MessageRow(item: item).id(item.id)
                        }
                        if model.busy {
                            ProgressView().padding(.leading, 4)
                        }
                    }
                    .padding()
                }
                .onChange(of: model.items.count) {
                    if let last = model.items.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Ask about your calendar, reminders or contacts", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await model.send(text) }
    }
}

struct EmptyState: View {
    @Environment(AppModel.self) private var model
    let examples = ["¿Qué tengo hoy?", "¿Qué recordatorios tengo pendientes?", "Organiza mi semana y dime si hay conflictos"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kith").font(.largeTitle.bold())
            Text("An agent over your own Apple data. Simple questions stay on device; every answer shows where it ran, what it cost, and the facts it was checked against.")
                .foregroundStyle(.secondary)
            ForEach(examples, id: \.self) { example in
                Button(example) { Task { await model.send(example) } }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical)
    }
}

struct MessageRow: View {
    let item: ChatItem
    @State private var showTrace = false

    var body: some View {
        VStack(alignment: item.fromPerson ? .trailing : .leading, spacing: 6) {
            Text(item.fromPerson ? AttributedString(item.text) : Format.markdown(item.text))
                .textSelection(.enabled)
                .padding(10)
                .background(item.fromPerson ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12))
            if let turn = item.turn {
                TurnBadge(turn: turn, expanded: $showTrace)
                if showTrace { TraceView(trace: turn.trace) }
            }
        }
        .frame(maxWidth: .infinity, alignment: item.fromPerson ? .trailing : .leading)
    }
}

/// The one-line answer to "where did this run and what did it cost".
struct TurnBadge: View {
    let turn: AgentTurn
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Label(turn.tier?.label ?? "Blocked", systemImage: turn.tier?.symbol ?? "hand.raised")
                Text("·")
                Text("\(turn.trace.usage.total) tok")
                Text("·")
                Text(Format.cost(turn.trace.costUSD))
                Text("·")
                Text(Format.ms(turn.trace.latencyMs))
                if turn.flaggedData {
                    Image(systemName: "exclamationmark.shield").foregroundStyle(.yellow)
                }
                if turn.outcome == .failedSafe {
                    Image(systemName: "xmark.shield").foregroundStyle(.red)
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show trace")
    }
}
