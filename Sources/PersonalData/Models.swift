import AgentCore
import Foundation

public struct CalendarEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var notes: String?
    public var calendar: String
    public var attendees: [String]

    public init(
        id: String, title: String, start: Date, end: Date, location: String? = nil, notes: String? = nil,
        calendar: String = "Personal", attendees: [String] = []
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.notes = notes
        self.calendar = calendar
        self.attendees = attendees
    }
}

public struct EventDraft: Sendable, Equatable {
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?

    public init(title: String, start: Date, end: Date, location: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
    }
}

public struct Reminder: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var due: Date?
    public var notes: String?
    public var list: String
    public var isCompleted: Bool
    /// 0 none, 1 high, 5 medium, 9 low (EventKit's scale).
    public var priority: Int

    public init(
        id: String, title: String, due: Date? = nil, notes: String? = nil, list: String = "Reminders",
        isCompleted: Bool = false, priority: Int = 0
    ) {
        self.id = id
        self.title = title
        self.due = due
        self.notes = notes
        self.list = list
        self.isCompleted = isCompleted
        self.priority = priority
    }
}

public struct Contact: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var givenName: String
    public var familyName: String
    public var emails: [String]
    public var phones: [String]
    public var organization: String?
    public var note: String?

    public var fullName: String { [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ") }

    public init(
        id: String, givenName: String, familyName: String, emails: [String] = [], phones: [String] = [],
        organization: String? = nil, note: String? = nil
    ) {
        self.id = id
        self.givenName = givenName
        self.familyName = familyName
        self.emails = emails
        self.phones = phones
        self.organization = organization
        self.note = note
    }
}

/// The person's data. The EventKit/Contacts adapter in the app and the in-memory store used
/// by tests and evals both conform, so the agent and the MCP server never know which one
/// they're talking to.
public protocol PersonalDataStore: Sendable {
    func events(from: Date, to: Date) async throws -> [CalendarEvent]
    func createEvent(_ draft: EventDraft) async throws -> CalendarEvent
    func reminders(includeCompleted: Bool) async throws -> [Reminder]
    func reminder(id: String) async throws -> Reminder?
    func completeReminder(id: String) async throws -> Reminder
    func searchContacts(_ query: String) async throws -> [Contact]
    func allContactNames() async throws -> [String]
}

public actor InMemoryStore: PersonalDataStore {
    public private(set) var eventList: [CalendarEvent]
    public private(set) var reminderList: [Reminder]
    public private(set) var contactList: [Contact]
    /// Every write that actually ran. The red-team oracle reads this, not the agent's words.
    public private(set) var writeLog: [String] = []
    private var nextID = 1

    public init(events: [CalendarEvent] = [], reminders: [Reminder] = [], contacts: [Contact] = []) {
        self.eventList = events
        self.reminderList = reminders
        self.contactList = contacts
    }

    public func events(from: Date, to: Date) async throws -> [CalendarEvent] {
        eventList.filter { $0.end > from && $0.start < to }.sorted { $0.start < $1.start }
    }

    public func createEvent(_ draft: EventDraft) async throws -> CalendarEvent {
        let event = CalendarEvent(id: "evt-new-\(nextID)", title: draft.title, start: draft.start, end: draft.end, location: draft.location)
        nextID += 1
        eventList.append(event)
        writeLog.append("calendar_create_event:\(event.id)")
        return event
    }

    public func reminders(includeCompleted: Bool) async throws -> [Reminder] {
        reminderList.filter { includeCompleted || !$0.isCompleted }
    }

    public func reminder(id: String) async throws -> Reminder? {
        reminderList.first { $0.id == id }
    }

    public func completeReminder(id: String) async throws -> Reminder {
        guard let i = reminderList.firstIndex(where: { $0.id == id }) else {
            throw ToolError.notFound("No reminder with id \(id).")
        }
        reminderList[i].isCompleted = true
        writeLog.append("reminders_complete:\(id)")
        return reminderList[i]
    }

    public func searchContacts(_ query: String) async throws -> [Contact] {
        let q = query.lowercased()
        return contactList.filter {
            $0.fullName.lowercased().contains(q) || ($0.organization?.lowercased().contains(q) ?? false)
                || $0.emails.contains { $0.lowercased().contains(q) }
        }
    }

    public func allContactNames() async throws -> [String] {
        contactList.map(\.fullName)
    }

    public func add(event: CalendarEvent) { eventList.append(event) }
    public func add(reminder: Reminder) { reminderList.append(reminder) }
    public func add(contact: Contact) { contactList.append(contact) }
}
