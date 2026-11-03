import Foundation

/// A fixed, synthetic week for tests, evals and the demo. No real person's data: every name
/// is invented and every email uses example.com/.edu. "Now" is Wednesday 4 November 2026,
/// 08:00 in Bogotá (UTC−5, no daylight saving).
public enum SyntheticData {
    public static let timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
    public static let now = at(2026, 11, 4, 8, 0)

    public static func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    public static var events: [CalendarEvent] {
        [
            CalendarEvent(id: "evt-101", title: "Clase: Arquitectura de Software", start: at(2026, 11, 2, 9, 0), end: at(2026, 11, 2, 10, 30),
                          location: "Edificio ML, salón 340", calendar: "Universidad"),
            CalendarEvent(id: "evt-102", title: "Reunión IEEE Computer Society", start: at(2026, 11, 3, 18, 0), end: at(2026, 11, 3, 19, 30),
                          location: "Sala de juntas W-101", calendar: "IEEE", attendees: ["Valentina Rojas", "Andrés Pardo"]),
            CalendarEvent(id: "evt-103", title: "Odontólogo", start: at(2026, 11, 4, 10, 0), end: at(2026, 11, 4, 10, 45),
                          location: "Clínica Dental Norte", calendar: "Personal"),
            CalendarEvent(id: "evt-104", title: "Proyecto de grado: revisión con Camila Herrera", start: at(2026, 11, 4, 14, 0),
                          end: at(2026, 11, 4, 15, 30), location: "Oficina 612", calendar: "Universidad", attendees: ["Camila Herrera"]),
            CalendarEvent(id: "evt-105", title: "Entrevista técnica", start: at(2026, 11, 4, 15, 0), end: at(2026, 11, 4, 16, 0),
                          location: "Videollamada", notes: "Llevar el demo del agente.", calendar: "Trabajo", attendees: ["Sofía Castro"]),
            CalendarEvent(id: "evt-106", title: "Gimnasio", start: at(2026, 11, 5, 6, 30), end: at(2026, 11, 5, 7, 45), calendar: "Personal"),
            CalendarEvent(id: "evt-107", title: "Almuerzo con Mateo", start: at(2026, 11, 6, 12, 30), end: at(2026, 11, 6, 13, 30),
                          location: "Usaquén", calendar: "Personal", attendees: ["Mateo Jiménez"]),
            CalendarEvent(id: "evt-108", title: "Cumpleaños de Laura", start: at(2026, 11, 7, 20, 0), end: at(2026, 11, 7, 23, 0),
                          location: "Casa de Laura", calendar: "Personal", attendees: ["Laura Gómez"]),
        ]
    }

    public static var reminders: [Reminder] {
        [
            Reminder(id: "rem-201", title: "Pagar la tarjeta de crédito", due: at(2026, 11, 5, 9, 0), list: "Finanzas", priority: 1),
            Reminder(id: "rem-202", title: "Entregar informe del proyecto de grado", due: at(2026, 11, 6, 23, 0), list: "Universidad", priority: 1),
            Reminder(id: "rem-203", title: "Comprar regalo para Laura", due: at(2026, 11, 7, 12, 0), list: "Personal", priority: 5),
            Reminder(id: "rem-204", title: "Renovar pasaporte", list: "Personal", priority: 9),
            Reminder(id: "rem-205", title: "Leer el capítulo 4 de DDIA", list: "Universidad", isCompleted: true),
        ]
    }

    public static var contacts: [Contact] {
        [
            Contact(id: "con-301", givenName: "Valentina", familyName: "Rojas", emails: ["valentina.rojas@example.com"],
                    phones: ["+57 300 111 2233"], organization: "IEEE Computer Society Uniandes"),
            Contact(id: "con-302", givenName: "Andrés", familyName: "Pardo", emails: ["andres.pardo@example.com"]),
            Contact(id: "con-303", givenName: "Camila", familyName: "Herrera", emails: ["c.herrera@example.edu"], organization: "Universidad"),
            Contact(id: "con-304", givenName: "Mateo", familyName: "Jiménez", phones: ["+57 310 555 0101"]),
            Contact(id: "con-305", givenName: "Laura", familyName: "Gómez", emails: ["laura.gomez@example.com"]),
            Contact(id: "con-306", givenName: "Sofía", familyName: "Castro", emails: ["sofia.castro@example.com"], organization: "Fintech"),
        ]
    }

    public static func store() -> InMemoryStore {
        InMemoryStore(events: events, reminders: reminders, contacts: contacts)
    }
}
