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
                LazyVStack(alignment: .leading, spacing: 26) {
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
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: 780)
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
                        .frame(maxWidth: 780)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.kithPaper)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.kithLine).frame(height: 1) }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Composer(draft: $draft) { send(draft) }
                    .frame(maxWidth: 780)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
                    .background(Color.kithPaper)
            }
        }
        .background(Color.kithPaper)
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

/// The home screen: who Kith is, what it promises, a few questions to start with, and where
/// answers may run right now.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    let send: (String) -> Void

    private let suggestions: [(symbol: String, text: String, tint: Color)] = [
        ("calendar", "¿Qué tengo hoy?", .kithMoss),
        ("checklist", "¿Qué recordatorios tengo pendientes?", .kithAmber),
        ("calendar.badge.exclamationmark", "Organiza mi semana y dime si hay conflictos", .kithDusk),
        ("calendar.badge.plus", "Agenda almuerzo con Mateo el viernes a la 1", .kithClay),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    KithMark(size: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Kith").font(.kithDisplay(17)).foregroundStyle(Color.kithInk)
                        Text("Your calendar, reminders and contacts")
                            .font(.footnote)
                            .foregroundStyle(Color.kithMuted)
                    }
                }
                Text("Ask about your week")
                    .font(.kithDisplay(36))
                    .foregroundStyle(Color.kithInk)
                    .padding(.top, 6)
                Text("Kith reads your Calendar, Reminders and Contacts, checks every answer against them, and never changes anything without your OK.")
                    .font(.title3)
                    .foregroundStyle(Color.kithMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PromiseStrip()

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Try asking")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                    ForEach(suggestions, id: \.text) { s in
                        SuggestionCard(symbol: s.symbol, text: s.text, tint: s.tint) { send(s.text) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Where answers may run")
                WhereAnswersRun()
            }
        }
        .padding(.top, 18)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Color.kithMuted)
    }
}

/// The three promises behind every answer, each in the colour it has everywhere else.
/// Side by side when there is room, stacked on a phone.
struct PromiseStrip: View {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    private let items: [(symbol: String, title: String, text: String, tint: Color)] = [
        ("checkmark.shield.fill", "Checked", "Every time, name and figure must come from your data.", .kithLeaf),
        ("hand.raised.fill", "Held", "Changes wait for your OK, whoever proposes them.", .kithAmber),
        ("eye.slash.fill", "Guarded", "Text that tries to instruct the assistant is withheld.", .kithCoral),
    ]

    var body: some View {
        #if os(iOS)
            if sizeClass == .compact {
                VStack(alignment: .leading, spacing: 8) { cells }
            } else {
                HStack(alignment: .top, spacing: 10) { cells }
            }
        #else
            HStack(alignment: .top, spacing: 10) { cells }
        #endif
    }

    private var cells: some View {
        ForEach(items, id: \.title) { item in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 30, height: 30)
                    .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.callout.weight(.semibold)).foregroundStyle(Color.kithInk)
                    Text(item.text)
                        .font(.footnote)
                        .foregroundStyle(Color.kithMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .kithCard(radius: 14, padding: 12)
        }
    }
}

struct SuggestionCard: View {
    let symbol: String
    let text: String
    var tint: Color = .kithMoss
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.kithInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(hovering ? tint : Color.kithMuted.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kithSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? tint.opacity(0.55) : Color.kithLine)
            )
            .offset(y: hovering ? -1 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy(duration: 0.2)) { hovering = h } }
    }
}

/// The three places an answer can run, which ones the privacy mode allows, and whether each
/// is ready. Choosing one sets the privacy mode that allows up to it.
struct WhereAnswersRun: View {
    @Environment(AppModel.self) private var model

    private let order: [(tier: Tier, mode: PrivacyMode, note: String)] = [
        (.onDevice, .deviceOnly, "Apple's model, never leaves this device"),
        (.localOpen, .ownHardware, "An open model on your Mac"),
        (.claude, .allowCloud, "Only if nothing local fits"),
    ]

    private func allowed(_ tier: Tier) -> Bool {
        switch model.settings.privacy {
        case .deviceOnly: return tier == .onDevice
        case .ownHardware: return tier != .claude
        case .allowCloud: return true
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(order.enumerated()), id: \.offset) { index, entry in
                let profile = model.profile(entry.tier)
                let on = allowed(entry.tier)
                Button {
                    Task { await model.setPrivacy(entry.mode) }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: entry.tier.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(on ? Color.white : Color.kithMuted)
                                .frame(width: 28, height: 28)
                                .background(on ? entry.tier.tint : Color.kithSunken, in: Circle())
                            Text(entry.tier.label)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(on ? Color.kithInk : Color.kithMuted)
                            Spacer(minLength: 0)
                        }
                        Text(entry.note)
                            .font(.caption)
                            .foregroundStyle(Color.kithMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(!on ? Color.kithMuted.opacity(0.4) : (profile?.available ?? false) ? Color.kithLeaf : Color.kithAmber)
                                .frame(width: 6, height: 6)
                            Text(!on ? "Off" : (profile?.available ?? false) ? "Ready" : "Not set up")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.kithMuted)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(entry.mode.explanation)
                if index < order.count - 1 {
                    Rectangle().fill(Color.kithLine).frame(width: 1).padding(.vertical, 10)
                }
            }
        }
        .background(Color.kithSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.kithLine))
    }
}

// MARK: - Messages

struct MessageRow: View {
    @Environment(AppModel.self) private var model
    let item: ChatItem
    @State private var showDetails: Bool

    init(item: ChatItem, showDetails: Bool = false) {
        self.item = item
        _showDetails = State(initialValue: showDetails)
    }

    var body: some View {
        if item.fromPerson {
            HStack {
                Spacer(minLength: 80)
                Text(item.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Color.kithMoss, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        } else if let symbol = item.notice {
            Label(item.text, systemImage: symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(symbol.hasPrefix("checkmark") ? Color.kithLeaf : Color.kithMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background((symbol.hasPrefix("checkmark") ? Color.kithLeaf : Color.kithMuted).opacity(0.1), in: Capsule())
        } else {
            HStack(alignment: .top, spacing: 12) {
                KithMark(size: 28)
                VStack(alignment: .leading, spacing: 12) {
                    Text(Format.markdown(item.text))
                        .foregroundStyle(Color.kithInk)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if let turn = item.turn {
                        AnswerFooter(turn: turn, expanded: $showDetails)
                        if showDetails {
                            TraceView(trace: turn.trace)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { if model.expandTraces { showDetails = true } }
        }
    }
}

struct ThinkingRow: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 12) {
            KithMark(size: 28)
                .scaleEffect(phase ? 1 : 0.92)
                .opacity(phase ? 1 : 0.7)
            Text("Thinking…")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.kithMuted)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { phase = true } }
    }
}

// MARK: - Answer footer

/// Under every answer: was it checked, where did it run, how long and what it cost.
/// "How this was answered" opens the full trace.
struct AnswerFooter: View {
    let turn: AgentTurn
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { statusChips }
                VStack(alignment: .leading, spacing: 6) { statusChips }
            }
            HStack(spacing: 10) {
                meta
                Spacer(minLength: 8)
                detailsButton
            }
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
            HStack(spacing: 4) {
                Text(expanded ? "Hide details" : "How this was answered")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.kithMoss)
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if let tier = turn.tier {
                HStack(spacing: 4) {
                    Image(systemName: tier.symbol)
                    Text(tier.label)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(tier.tint)
            } else {
                Text("No model ran").font(.caption.weight(.semibold)).foregroundStyle(Color.kithMuted)
            }
            Text("·").foregroundStyle(Color.kithMuted)
            Text(Format.ms(turn.trace.latencyMs))
            Text("·").foregroundStyle(Color.kithMuted)
            Text(Format.cost(turn.trace.costUSD))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(Color.kithMuted)
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
            return [TurnStatus(symbol: "hand.raised.fill", text: "Blocked before any model ran", color: .kithCoral)]
        case .failedSafe:
            out.append(TurnStatus(symbol: "xmark.shield.fill", text: "Couldn't verify, so no answer", color: .kithCoral))
        case .answered, .awaitingConfirmation:
            let checked = turn.trace.spans.last(where: { $0.kind == .outputGuard && $0.status == .ok })?
                .detail["claims_checked"].flatMap(Int.init) ?? 0
            if checked > 0 {
                out.append(TurnStatus(symbol: "checkmark.shield.fill",
                                      text: "Checked \(checked) \(checked == 1 ? "fact" : "facts") against your data", color: .kithLeaf))
            } else {
                out.append(TurnStatus(symbol: "checkmark.shield", text: "Nothing to check", color: .kithMuted))
            }
        }
        if turn.outcome == .awaitingConfirmation {
            out.append(TurnStatus(symbol: "hourglass", text: "Waiting for your OK", color: .kithAmber))
        }
        if turn.flaggedData {
            out.append(TurnStatus(symbol: "eye.slash.fill", text: "Suspicious text withheld", color: .kithCoral))
        }
        return out
    }
}

struct StatusChip: View {
    let status: TurnStatus

    var body: some View {
        Label(status.text, systemImage: status.symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.12), in: Capsule())
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
            TextField("Ask Kith about your week", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.kithInk)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit { if canSend { send() } }
                .padding(.vertical, 8)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(canSend ? Color.kithMoss : Color.kithMuted.opacity(0.3), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(Color.kithSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(focused ? Color.kithMoss.opacity(0.6) : Color.kithLine, lineWidth: focused ? 1.5 : 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.kithMoss)
                .frame(width: 32, height: 32)
                .background(Color.kithMoss.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Where answers may run: \(model.settings.privacy.title)")
        .accessibilityLabel("Where answers may run: \(model.settings.privacy.title)")
    }
}
