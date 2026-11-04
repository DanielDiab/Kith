import AgentCore
import AppIntents
import Foundation
import PersonalData

/// Ask Kith anything through Siri, Shortcuts or Spotlight. Runs the full agent: input guard,
/// router, gated tools, output guard. The client is `.siri`, so the trace says where it came from.
struct AskKithIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Kith"
    static let description = IntentDescription("Ask about your calendar, reminders or contacts.")

    @Parameter(title: "Question")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let turn = await KithRuntime.shared.respond(to: question, client: .siri, history: [])
        return .result(dialog: IntentDialog(stringLiteral: turn.reply))
    }
}

/// "What's next?" without a model: one read tool, formatted in code. Instant and free.
struct NextEventsIntent: AppIntent {
    static let title: LocalizedStringResource = "What's next in my calendar"
    static let description = IntentDescription("Lists your next events for the coming day.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = KithRuntime.shared
        let now = await runtime.settings.dataSource == .demo ? SyntheticData.now : Date()
        let tz = await runtime.timeZone
        let format = LocalFormat(timeZone: tz)
        let result = try await runtime.read(
            "calendar_list_events",
            ["from": .string(format.iso(now)), "to": .string(format.iso(now.addingTimeInterval(24 * 3600)))])
        let events = result["events"]?.arrayValue ?? []
        guard !events.isEmpty else { return .result(dialog: "Nothing in the next 24 hours.") }
        let lines = events.prefix(5).compactMap { e -> String? in
            guard let title = e["title"]?.stringValue, let when = e["when_local"]?.stringValue else { return nil }
            return "\(title), \(when)"
        }
        return .result(dialog: IntentDialog(stringLiteral: lines.joined(separator: ". ")))
    }
}

/// Marks a reminder done. Siri asks the person to confirm first; only then does the write run,
/// through the same pending store and trace as the app.
struct CompleteReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete a reminder"
    static let description = IntentDescription("Marks one of your reminders as done after you confirm.")

    @Parameter(title: "Reminder")
    var reminder: ReminderEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation(result: .result(dialog: IntentDialog(stringLiteral: "Mark “\(reminder.title)” as done?")))
        _ = try await KithRuntime.shared.runConfirmedWrite(
            "reminders_complete", ["id": .string(reminder.id)], summary: "Mark “\(reminder.title)” as done")
        return .result(dialog: IntentDialog(stringLiteral: "Done: “\(reminder.title)”."))
    }
}

struct ReminderEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Reminder"
    static let defaultQuery = ReminderQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct ReminderQuery: EntityQuery {
    func entities(for identifiers: [ReminderEntity.ID]) async throws -> [ReminderEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ReminderEntity] {
        try await KithRuntime.shared.openReminders().map { ReminderEntity(id: $0.id, title: $0.title) }
    }
}

struct KithShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextEventsIntent(),
            phrases: ["What's next in \(.applicationName)", "Qué sigue en \(.applicationName)"],
            shortTitle: "What's next",
            systemImageName: "calendar")
        AppShortcut(
            intent: AskKithIntent(),
            phrases: ["Ask \(.applicationName)", "Pregúntale a \(.applicationName)"],
            shortTitle: "Ask Kith",
            systemImageName: "bubble.left.and.text.bubble.right")
        AppShortcut(
            intent: CompleteReminderIntent(),
            phrases: ["Complete a reminder in \(.applicationName)", "Completa un recordatorio en \(.applicationName)"],
            shortTitle: "Complete reminder",
            systemImageName: "checkmark.circle")
    }
}
