import AgentCore
import Foundation

/// The five tools the agent and the MCP server expose. Reads return instants with the
/// person's offset plus a `_local` string; writes only describe what they'll do until the
/// person confirms.
public enum PersonalTools {
    public static func all(store: any PersonalDataStore, format: LocalFormat) -> [any ToolHandler] {
        [
            ListEvents(store: store, format: format),
            CreateEvent(store: store, format: format),
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

    public let spec = ToolSpec(
        name: "calendar_list_events",
        description: "List the person's calendar events between two moments. Use it for any question about their schedule.",
        effect: .read,
        parameters: [
            ToolParameter("from", type: "date-time", description: "Start, ISO 8601 with offset (2026-11-04T00:00:00-05:00) or a day (2026-11-04)."),
            ToolParameter("to", type: "date-time", description: "End, same format. A day means the end of that day."),
        ]
    )

    public func call(_ arguments: JSONValue) async throws -> JSONValue {
        guard let fromText = arguments["from"]?.stringValue, let from = format.parse(fromText),
              let toText = arguments["to"]?.stringValue, let to = format.parse(toText, endOfDay: true)
        else {
            throw ToolError.invalidArguments("from and to must look like 2026-11-04T09:00:00-05:00 or 2026-11-04.")
        }
        guard to > from else { throw ToolError.invalidArguments("to must be after from.") }
        guard to.timeIntervalSince(from) <= 31 * 86_400 else {
            throw ToolError.invalidArguments("The range can be at most 31 days.")
        }
        let events = try await store.events(from: from, to: to)
        return [
            "events": .array(events.map { PersonalTools.eventJSON($0, format) }),
            "count": .number(Double(events.count)),
            "range_local": .string("\(format.dateTime(from)) – \(format.dateTime(to))"),
        ]
    }
}

public struct CreateEvent: ToolHandler {
    let store: any PersonalDataStore
    let format: LocalFormat

    public let spec = ToolSpec(
        name: "calendar_create_event",
        description: "Propose a new calendar event. It is held until the person confirms it in the app.",
        effect: .write,
        parameters: [
            ToolParameter("title", type: "string", description: "Event title."),
            ToolParameter("start", type: "date-time", description: "Start, ISO 8601 with offset."),
            ToolParameter("end", type: "date-time", description: "End, ISO 8601 with offset."),
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
        description: "List the person's reminders. Open ones by default.",
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
        description: "Propose marking a reminder as done. It is held until the person confirms it in the app.",
        effect: .write,
        parameters: [ToolParameter("id", type: "string", description: "The reminder id from reminders_list.")]
    )

    public func call(_ arguments: JSONValue) async throws -> JSONValue {
        guard let id = arguments["id"]?.stringValue else { throw ToolError.invalidArguments("Need the reminder id.") }
        let r = try await store.completeReminder(id: id)
        return ["completed": PersonalTools.reminderJSON(r, format)]
    }

    public func preview(_ arguments: JSONValue) async -> String {
        guard let id = arguments["id"]?.stringValue else { return "Complete a reminder (missing id)" }
        if let r = try? await store.reminder(id: id) { return "Mark “\(r.title)” as done" }
        return "Mark reminder \(id) as done (not found)"
    }
}

public struct SearchContacts: ToolHandler {
    let store: any PersonalDataStore

    public let spec = ToolSpec(
        name: "contacts_search",
        description: "Find the person's contacts by name, organization or email.",
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
