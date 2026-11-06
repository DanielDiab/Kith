import AgentCore
import Foundation

/// The five tools the agent and the MCP server expose. Reads return instants with the
/// person's offset plus a `_local` string; writes only describe what they'll do until the
/// person confirms.
public enum PersonalTools {
    /// `now` sets the default range of `calendar_list_events` (today and the six days after).
    public static func all(
        store: any PersonalDataStore, format: LocalFormat, now: @escaping @Sendable () -> Date = { Date() }
    ) -> [any ToolHandler] {
        [
            ListEvents(store: store, format: format, now: now),
            CreateEvent(store: store, format: format, now: now),
            ListReminders(store: store, format: format),
            CompleteReminder(store: store, format: format),
            SearchContacts(store: store),
        ]
    }

    static func eventJSON(_ e: CalendarEvent, _ f: LocalFormat) -> JSONValue {
        var o: [String: JSONValue] = [
            "id": .string(e.id),
            "title": .string(e.title),
            "start": .string(f.iso(e.start)),
            "end": .string(f.iso(e.end)),
            "when_local": .string(f.range(e.start, e.end)),
            "duration_minutes": .number((e.end.timeIntervalSince(e.start) / 60).rounded()),
            "calendar": .string(e.calendar),
        ]
        if let l = e.location { o["location"] = .string(l) }
        if let n = e.notes { o["notes"] = .string(n) }
        if !e.attendees.isEmpty { o["attendees"] = .array(e.attendees.map { .string($0) }) }
        return .object(o)
    }

    static func reminderJSON(_ r: Reminder, _ f: LocalFormat) -> JSONValue {
        var o: [String: JSONValue] = [
            "id": .string(r.id),
            "title": .string(r.title),
            "list": .string(r.list),
            "completed": .bool(r.isCompleted),
        ]
        if let due = r.due {
            o["due"] = .string(f.iso(due))
            o["due_local"] = .string(f.dateTime(due))
        }
        if r.priority == 1 { o["priority"] = "high" } else if r.priority == 5 { o["priority"] = "medium" } else if r.priority == 9 { o["priority"] = "low" }
        if let n = r.notes { o["notes"] = .string(n) }
        return .object(o)
    }
}

public struct ListEvents: ToolHandler {
    let store: any PersonalDataStore
    let format: LocalFormat
    var now: @Sendable () -> Date = { Date() }

    public let spec = ToolSpec(
        name: "calendar_list_events",
        description: "List the person's calendar events with title, local time, duration, place, attendees and notes, "
            + "and which of them overlap. Use it for any question about their schedule: what, when, how long, where, with whom, conflicts.",
        effect: .read,
        parameters: [
            ToolParameter("from", type: "date-time", description: "First day (2026-11-04) or instant with offset. Omit both for the coming week.", required: false),
            ToolParameter("to", type: "date-time", description: "Last day, included, or instant. Omit for just the from day.", required: false),
        ]
    )

    /// Small models often leave the range out or send only one end, so both are optional. A
    /// lone `from` means that day: asked "¿Tengo algo el jueves?" with the whole week in hand,
    /// the on-device model listed Friday's lunch under Thursday.
    public func call(_ arguments: JSONValue) async throws -> JSONValue {
        let fromText = arguments["from"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        let toText = arguments["to"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        let from: Date
        if let fromText {
            guard let parsed = format.parse(fromText) else { throw Self.badDate }
            from = parsed
        } else {
            from = format.startOfDay(now())
        }
        let to: Date
        if let toText {
            guard let parsed = format.parse(toText, endOfDay: true) else { throw Self.badDate }
            to = parsed
        } else {
            to = format.startOfDay(from, addingDays: fromText == nil ? 7 : 1)
        }
        guard to > from else { throw ToolError.invalidArguments("to must be after from.") }
        guard to.timeIntervalSince(from) <= 31 * 86_400 else {
            throw ToolError.invalidArguments("The range can be at most 31 days.")
        }
        let events = try await store.events(from: from, to: to)
        return [
            "events": .array(events.map { PersonalTools.eventJSON($0, format) }),
            "count": .number(Double(events.count)),
            "overlaps": .array(Self.overlaps(events).map { a, b in
                [
                    "events": [.string(a.title), .string(b.title)],
                    "overlap_local": .string(format.range(b.start, min(a.end, b.end))),
                ]
            }),
            "range_local": .string("\(format.dateTime(from)) – \(format.dateTime(to))"),
        ]
    }

    /// Pairs of events that overlap in time. Computed here because small models can't be
    /// trusted with interval arithmetic: asked for conflicts, the on-device model and Qwen 8B
    /// both missed a 14:00–15:30 review overlapping a 15:00 interview.
    static func overlaps(_ events: [CalendarEvent]) -> [(CalendarEvent, CalendarEvent)] {
        let sorted = events.sorted { $0.start < $1.start }
        var out: [(CalendarEvent, CalendarEvent)] = []
        for (i, a) in sorted.enumerated() {
            for b in sorted[(i + 1)...] where b.start < a.end { out.append((a, b)) }
        }
        return out
    }

    static let badDate = ToolError.invalidArguments("from and to must look like 2026-11-04 or 2026-11-04T09:00:00-05:00.")
}

public struct CreateEvent: ToolHandler {
    let store: any PersonalDataStore
    let format: LocalFormat
    var now: @Sendable () -> Date = { Date() }

    public let spec = ToolSpec(
        name: "calendar_create_event",
        description: "Propose a new calendar event when the person asks to schedule something. It is held until they confirm it in the app.",
        effect: .write,
        parameters: [
            ToolParameter("title", type: "string", description: "Event title."),
            ToolParameter("start", type: "date-time", description: "Start, ISO 8601 with offset (2026-11-06T07:00:00-05:00)."),
            ToolParameter("end", type: "date-time", description: "End, same format."),
            ToolParameter("location", type: "string", description: "Optional place.", required: false),
        ]
    )

    func draft(_ a: JSONValue) throws -> EventDraft {
        guard let title = a["title"]?.stringValue, !title.isEmpty,
              let s = a["start"]?.stringValue.flatMap({ format.parse($0) }),
              let e = a["end"]?.stringValue.flatMap({ format.parse($0) }), e > s
        else {
            throw ToolError.invalidArguments("Need title, and start before end as 2026-11-04T09:00:00-05:00.")
        }
        return EventDraft(title: title, start: s, end: e, location: a["location"]?.stringValue)
    }

    public func call(_ arguments: JSONValue) async throws -> JSONValue {
        let event = try await store.createEvent(try draft(arguments))
        return ["created": PersonalTools.eventJSON(event, format)]
    }

    /// The day and the start and end must be the ones the person said, when they said any.
    public func resolve(_ arguments: JSONValue, personSaid: String) async throws -> JSONValue {
        let d = try draft(arguments)
        let today = now()
        let days = StatedTimes.days(in: personSaid, today: format.weekday(today))
        if !days.isEmpty {
            let offset = format.daysBetween(today, d.start)
            guard days.contains(offset) else {
                let said = days.sorted().map { format.isoDay(format.startOfDay(today, addingDays: $0)) }.joined(separator: " or ")
                throw ToolError.invalidArguments(
                    "The person asked for \(said), but start is on \(format.isoDay(d.start)). Call again on the day they said.")
            }
        }
        let stated = StatedTimes.parse(personSaid)
        guard !stated.isEmpty else { return arguments }
        let (sh, sm) = format.hourMinute(d.start)
        let (eh, em) = format.hourMinute(d.end)
        if let range = stated.range {
            guard range.start.matches(hour: sh, minute: sm), range.end.matches(hour: eh, minute: em) else {
                throw ToolError.invalidArguments(
                    "The person asked for \(range.start.label) to \(range.end.label), but start is \(format.time(d.start)) and end is "
                        + "\(format.time(d.end)). Call again with exactly those times.")
            }
        } else if !stated.times.contains(where: { $0.matches(hour: sh, minute: sm) }) {
            let said = stated.times.map(\.label).joined(separator: ", ")
            throw ToolError.invalidArguments(
                "The person said \(said), but start is \(format.time(d.start)). Call again with the start they asked for.")
        }
        return arguments
    }

    public func preview(_ arguments: JSONValue) async -> String {
        guard let d = try? draft(arguments) else { return "Create an event (invalid arguments)" }
        let place = d.location.map { " · \($0)" } ?? ""
        return "Create “\(d.title)” · \(format.range(d.start, d.end))\(place)"
    }
}

public struct ListReminders: ToolHandler {
    let store: any PersonalDataStore
    let format: LocalFormat

    public let spec = ToolSpec(
        name: "reminders_list",
        description: "List the person's reminders (tasks) with due date and priority. Open ones by default.",
        effect: .read,
        parameters: [
            ToolParameter("include_completed", type: "boolean", description: "Also list completed reminders.", required: false)
        ]
    )

    public func call(_ arguments: JSONValue) async throws -> JSONValue {
        let all = try await store.reminders(includeCompleted: arguments["include_completed"]?.boolValue ?? false)
        return ["reminders": .array(all.map { PersonalTools.reminderJSON($0, format) }), "count": .number(Double(all.count))]
    }
}

public struct CompleteReminder: ToolHandler {
    let store: any PersonalDataStore
    let format: LocalFormat

    public let spec = ToolSpec(
        name: "reminders_complete",
        description: "Propose marking a reminder as done when the person asks. It is held until they confirm it in the app.",
        effect: .write,
        parameters: [
            ToolParameter("title", type: "string", description: "Words from the reminder's title, like pasaporte.", required: false),
            ToolParameter("id", type: "string", description: "Or its id from reminders_list.", required: false),
        ]
    )

    /// Runs only after confirmation, and by then `resolve` has replaced any title with an id.
    public func call(_ arguments: JSONValue) async throws -> JSONValue {
        let id = try await resolveID(arguments)
        let r = try await store.completeReminder(id: id)
        return ["completed": PersonalTools.reminderJSON(r, format)]
    }

    /// A title is looked up among open reminders and must name exactly one, so the held write
    /// carries an id and the confirmation card shows the reminder that will change.
    public func resolve(_ arguments: JSONValue, personSaid: String) async throws -> JSONValue {
        ["id": .string(try await resolveID(arguments))]
    }

    func resolveID(_ arguments: JSONValue) async throws -> String {
        if let id = arguments["id"]?.stringValue, !id.isEmpty {
            guard (try? await store.reminder(id: id)) != nil else { throw ToolError.notFound("No reminder has the id \(id).") }
            return id
        }
        guard let title = arguments["title"]?.stringValue, title.count >= 3 else {
            throw ToolError.invalidArguments("Give title (words from the reminder) or id.")
        }
        let words = TextMatch.words(title)
        let open = try await store.reminders(includeCompleted: false)
        let matches = open.filter { r in
            let have = Set(TextMatch.words(r.title))
            return !words.isEmpty && words.allSatisfy { w in have.contains { $0.hasPrefix(w) || w.hasPrefix($0) } }
        }
        switch matches.count {
        case 1: return matches[0].id
        case 0: throw ToolError.notFound("No open reminder matches “\(title)”. Call reminders_list to see them.")
        default:
            let names = matches.prefix(5).map { "\($0.title) (\($0.id))" }.joined(separator: ", ")
            throw ToolError.invalidArguments("Several reminders match: \(names). Call again with the id.")
        }
    }

    public func preview(_ arguments: JSONValue) async -> String {
        guard let id = arguments["id"]?.stringValue else { return "Complete a reminder (missing id)" }
        if let r = try? await store.reminder(id: id) { return "Mark “\(r.title)” as done" }
        return "Mark reminder \(id) as done (not found)"
    }
}

/// Word matching for titles named in a request: folded, short words and articles dropped.
enum TextMatch {
    static let stop: Set<String> = ["el", "la", "los", "las", "de", "del", "un", "una", "the", "a", "an", "of", "my", "mi", "to", "para"]

    static func words(_ s: String) -> [String] {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !stop.contains($0) }
    }
}

public struct SearchContacts: ToolHandler {
    let store: any PersonalDataStore

    public let spec = ToolSpec(
        name: "contacts_search",
        description: "Find the person's contacts by name, organization or email: emails, phones, organization.",
        effect: .read,
        parameters: [ToolParameter("query", type: "string", description: "Part of a name, organization or email.")]
    )

    public func call(_ arguments: JSONValue) async throws -> JSONValue {
        guard let q = arguments["query"]?.stringValue, q.count >= 2 else {
            throw ToolError.invalidArguments("The query needs at least two characters.")
        }
        let found = try await store.searchContacts(q).prefix(10)
        let items: [JSONValue] = found.map { c in
            var o: [String: JSONValue] = ["id": .string(c.id), "name": .string(c.fullName)]
            if !c.emails.isEmpty { o["emails"] = .array(c.emails.map { .string($0) }) }
            if !c.phones.isEmpty { o["phones"] = .array(c.phones.map { .string($0) }) }
            if let org = c.organization { o["organization"] = .string(org) }
            if let note = c.note { o["note"] = .string(note) }
            return .object(o)
        }
        return ["contacts": .array(items), "count": .number(Double(items.count))]
    }
}
