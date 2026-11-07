import AgentCore
import SwiftUI

/// The conversation: a welcome with suggestions, the answers, and a composer that always
/// says where answers may run. Changes waiting for confirmation sit above the conversation.
struct ChatView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if model.items.isEmpty {
                        WelcomeView { text in send(text) }
                    }
                    ForEach(model.items) { item in
                        MessageRow(item: item).id(item.id)
                    }
                    if model.busy {
                        ThinkingRow().id("thinking")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .onChange(of: model.items.count) {
                if let last = model.items.last { withAnimation(.snappy) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: model.busy) {
                if model.busy { withAnimation(.snappy) { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !model.pending.isEmpty {
                    PendingWritesView()
                        .frame(maxWidth: 760)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Composer(draft: $draft) { send(draft) }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
        .animation(.snappy, value: model.pending.count)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.snappy) { model.newConversation() }
                } label: {
                    Label("New Conversation", systemImage: "square.and.pencil")
                }
                .disabled(model.items.isEmpty || model.busy)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !model.busy else { return }
        draft = ""
        Task { await model.send(trimmed) }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    let send: (String) -> Void

    private let suggestions: [(symbol: String, text: String)] = [
        ("calendar", "¿Qué tengo hoy?"),
        ("checklist", "¿Qué recordatorios tengo pendientes?"),
        ("calendar.badge.exclamationmark", "Organiza mi semana y dime si hay conflictos"),
        ("calendar.badge.plus", "Agenda almuerzo con Mateo el viernes a la 1"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.bottom, 6)
                Text("Ask about your week")
                    .font(.largeTitle.weight(.bold))
                Text("Kith reads your Calendar, Reminders and Contacts, checks every answer against them, and never changes anything without your OK.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                ForEach(suggestions, id: \.text) { s in
                    SuggestionCard(symbol: s.symbol, text: s.text) { send(s.text) }
                }
            }

            Label {
                Text(model.settings.privacy.explanation)
            } icon: {
                Image(systemName: model.settings.privacy.symbol)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }
}

struct SuggestionCard: View {
    let symbol: String
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(hovering ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Messages

struct MessageRow: View {
    let item: ChatItem
    @State private var showDetails: Bool

    init(item: ChatItem, showDetails: Bool = false) {
        self.item = item
        _showDetails = State(initialValue: showDetails)
    }

    var body: some View {
        if item.fromPerson {
            HStack {
                Spacer(minLength: 60)
                Text(item.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else if let symbol = item.notice {
            Label(item.text, systemImage: symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(Format.markdown(item.text))
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let turn = item.turn {
                    AnswerFooter(turn: turn, expanded: $showDetails)
                    if showDetails {
                        TraceView(trace: turn.trace)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Thinking…").foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

// MARK: - Answer footer

/// Under every answer: was it checked, where did it run, how long and what it cost.
/// "Details" opens the full trace.
struct AnswerFooter: View {
    let turn: AgentTurn
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    statusChips
                    Spacer(minLength: 8)
                    detailsButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) { statusChips }
                    detailsButton
                }
            }
            meta
        }
    }

    private var statusChips: some View {
        ForEach(TurnStatus.of(turn), id: \.text) { status in
            StatusChip(status: status)
        }
    }

    private var detailsButton: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            HStack(spacing: 3) {
                Text(expanded ? "Hide details" : "How this was answered")
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .font(.footnote.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private var meta: some View {
        HStack(spacing: 5) {
            if let tier = turn.tier {
                Image(systemName: tier.symbol)
                Text(tier.label)
            } else {
                Text("No model ran")
            }
            Text("·")
            Text(Format.ms(turn.trace.latencyMs))
            Text("·")
            Text(Format.cost(turn.trace.costUSD))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.tertiary)
    }
}

/// One plain-language fact about a turn, shown as a tinted chip.
struct TurnStatus: Equatable {
    var symbol: String
    var text: String
    var color: Color

    static func of(_ turn: AgentTurn) -> [TurnStatus] {
        var out: [TurnStatus] = []
        switch turn.outcome {
        case .blocked:
            return [TurnStatus(symbol: "hand.raised.fill", text: "Blocked before any model ran", color: .red)]
        case .failedSafe:
            out.append(TurnStatus(symbol: "xmark.shield.fill", text: "Couldn't verify, so no answer", color: .red))
        case .answered, .awaitingConfirmation:
            let checked = turn.trace.spans.last(where: { $0.kind == .outputGuard && $0.status == .ok })?
                .detail["claims_checked"].flatMap(Int.init) ?? 0
            if checked > 0 {
                out.append(TurnStatus(symbol: "checkmark.shield.fill",
                                      text: "Checked \(checked) \(checked == 1 ? "fact" : "facts") against your data", color: .green))
            } else {
                out.append(TurnStatus(symbol: "checkmark.shield", text: "Nothing to check", color: .secondary))
            }
        }
        if turn.outcome == .awaitingConfirmation {
            out.append(TurnStatus(symbol: "hourglass", text: "Waiting for your OK", color: .orange))
        }
        if turn.flaggedData {
            out.append(TurnStatus(symbol: "exclamationmark.shield.fill", text: "Suspicious text withheld", color: .yellow))
        }
        return out
    }
}

struct StatusChip: View {
    let status: TurnStatus

    var body: some View {
        Label(status.text, systemImage: status.symbol)
            .font(.footnote.weight(.medium))
            .foregroundStyle(status.color == .yellow ? Color.orange : status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.13), in: Capsule())
            .lineLimit(1)
    }
}

// MARK: - Composer

struct Composer: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: String
    let send: () -> Void
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.busy
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PrivacyMenu()
            TextField("Ask Kith", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit { if canSend { send() } }
                .padding(.vertical, 7)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(canSend ? Color.accentColor : Color.secondary.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 6)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(Color.primary.opacity(focused ? 0.22 : 0.12))
        )
    }
}

/// Where answers may run, one click from the composer.
struct PrivacyMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Picker("Where answers may run", selection: Binding(
                get: { model.settings.privacy },
                set: { v in Task { await model.setPrivacy(v) } }
            )) {
                ForEach([PrivacyMode.deviceOnly, .ownHardware, .allowCloud], id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: model.settings.privacy.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Where answers may run: \(model.settings.privacy.title)")
        .accessibilityLabel("Where answers may run: \(model.settings.privacy.title)")
    }
}
