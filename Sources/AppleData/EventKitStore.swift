#if canImport(EventKit) && canImport(Contacts)
    import AgentCore
    import Contacts
    import EventKit
    import Foundation
    import PersonalData

    /// The person's real Calendar, Reminders and Contacts, behind the same `PersonalDataStore`
    /// protocol the synthetic week implements. The agent and the MCP server can't tell them apart.
    ///
    /// Access is requested per data type, the first time the person turns the source on in
    /// Settings: full access to events and reminders (macOS 14 / iOS 17 APIs) and contacts.
    public final class EventKitStore: PersonalDataStore, @unchecked Sendable {
        private let events = EKEventStore()
        private let contacts = CNContactStore()

        public init() {}

        public struct Access: Sendable, Equatable {
            public var calendar: Bool
            public var reminders: Bool
            public var contacts: Bool
        }

        public static func currentAccess() -> Access {
            Access(
                calendar: EKEventStore.authorizationStatus(for: .event) == .fullAccess,
                reminders: EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
                contacts: CNContactStore.authorizationStatus(for: .contacts) == .authorized)
        }

        public func requestAccess() async -> Access {
            let calendar = (try? await events.requestFullAccessToEvents()) ?? false
            let reminders = (try? await events.requestFullAccessToReminders()) ?? false
            let people = (try? await contacts.requestAccess(for: .contacts)) ?? false
            return Access(calendar: calendar, reminders: reminders, contacts: people)
        }

        // MARK: Events

        public func events(from: Date, to: Date) async throws -> [CalendarEvent] {
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                throw ToolError.permissionDenied("Kith doesn't have Calendar access. Turn it on in Settings.")
            }
            let predicate = events.predicateForEvents(withStart: from, end: to, calendars: nil)
            return events.events(matching: predicate).map(Self.map).sorted { $0.start < $1.start }
        }

        public func createEvent(_ draft: EventDraft) async throws -> CalendarEvent {
            let event = EKEvent(eventStore: events)
            event.title = draft.title
            event.startDate = draft.start
            event.endDate = draft.end
            event.location = draft.location
            guard let calendar = events.defaultCalendarForNewEvents else {
                throw ToolError.backend("There is no default calendar for new events.")
            }
            event.calendar = calendar
            do {
                try events.save(event, span: .thisEvent, commit: true)
            } catch {
                throw ToolError.backend("Calendar refused the event: \(error.localizedDescription)")
            }
            return Self.map(event)
        }

        static func map(_ e: EKEvent) -> CalendarEvent {
            CalendarEvent(
                id: e.eventIdentifier ?? e.calendarItemIdentifier,
                title: e.title ?? "",
                start: e.startDate,
                end: e.endDate,
                location: e.location,
                notes: e.notes,
                calendar: e.calendar?.title ?? "",
                attendees: (e.attendees ?? []).compactMap(\.name))
        }

        // MARK: Reminders

        public func reminders(includeCompleted: Bool) async throws -> [Reminder] {
            guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                throw ToolError.permissionDenied("Kith doesn't have Reminders access. Turn it on in Settings.")
            }
            let predicate = events.predicateForReminders(in: nil)
            let all: [Reminder] = await withCheckedContinuation { continuation in
                events.fetchReminders(matching: predicate) { found in
                    continuation.resume(returning: (found ?? []).map(Self.map))
                }
            }
            return all.filter { includeCompleted || !$0.isCompleted }
        }

        public func reminder(id: String) async throws -> Reminder? {
            (events.calendarItem(withIdentifier: id) as? EKReminder).map(Self.map)
        }

        public func completeReminder(id: String) async throws -> Reminder {
            guard let item = events.calendarItem(withIdentifier: id) as? EKReminder else {
                throw ToolError.notFound("No reminder with id \(id).")
            }
            item.isCompleted = true
            do {
                try events.save(item, commit: true)
            } catch {
                throw ToolError.backend("Reminders refused the change: \(error.localizedDescription)")
            }
            return Self.map(item)
        }

        static func map(_ r: EKReminder) -> Reminder {
            Reminder(
                id: r.calendarItemIdentifier,
                title: r.title ?? "",
                due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                notes: r.notes,
                list: r.calendar?.title ?? "",
                isCompleted: r.isCompleted,
                priority: r.priority)
        }

        // MARK: Contacts

        static let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey,
            CNContactPhoneNumbersKey, CNContactOrganizationNameKey,
        ] as [CNKeyDescriptor]

        public func searchContacts(_ query: String) async throws -> [Contact] {
            guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
                throw ToolError.permissionDenied("Kith doesn't have Contacts access. Turn it on in Settings.")
            }
            let byName = try contacts.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: Self.keys)
            return byName.map(Self.map)
        }

        public func allContactNames() async throws -> [String] {
            guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return [] }
            var names: [String] = []
            let request = CNContactFetchRequest(keysToFetch: [CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor])
            try contacts.enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                if name.contains(" ") { names.append(name) }
            }
            return names
        }

        static func map(_ c: CNContact) -> Contact {
            Contact(
                id: c.identifier,
                givenName: c.givenName,
                familyName: c.familyName,
                emails: c.emailAddresses.map { $0.value as String },
                phones: c.phoneNumbers.map { $0.value.stringValue },
                organization: c.organizationName.isEmpty ? nil : c.organizationName)
        }
    }
#endif
