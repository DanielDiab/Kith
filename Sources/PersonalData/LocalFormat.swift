import AgentCore
import Foundation

/// Human-readable local dates for tool results ("mié 4 nov 2026, 10:00").
///
/// Tools hand the model both the instant (ISO 8601 with the person's offset) and this local
/// string, so the model never converts time zones itself. Same principle as Charter's
/// `calcular_desglose`: if the model needs a value, a tool computes it.
/// Formatting is done by hand so output is identical on macOS, iOS and Linux CI.
public struct LocalFormat: Sendable {
    public enum Language: String, Sendable { case es, en }

    public var timeZone: TimeZone
    public var language: Language

    public init(timeZone: TimeZone, language: Language = .es) {
        self.timeZone = timeZone
        self.language = language
    }

    static let weekdaysES = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]
    static let weekdaysEN = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let monthsES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]
    static let monthsEN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    public func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let wd = (c.weekday ?? 1) - 1
        let mo = (c.month ?? 1) - 1
        switch language {
        case .es: return "\(Self.weekdaysES[wd]) \(c.day ?? 0) \(Self.monthsES[mo]) \(c.year ?? 0)"
        case .en: return "\(Self.weekdaysEN[wd]) \(c.day ?? 0) \(Self.monthsEN[mo]) \(c.year ?? 0)"
        }
    }

    public func time(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return (h < 10 ? "0" : "") + "\(h):" + (m < 10 ? "0" : "") + "\(m)"
    }

    /// Sunday 1 … Saturday 7, in the person's time zone.
    func weekday(_ date: Date) -> Int { calendar.component(.weekday, from: date) }

    /// Whole local days from `a`'s day to `b`'s day.
    func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    /// "2026-11-06".
    func isoDay(_ date: Date) -> String { String(iso(date).prefix(10)) }

    func hourMinute(_ date: Date) -> (Int, Int) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0, c.minute ?? 0)
    }

    public func dateTime(_ date: Date) -> String { "\(day(date)), \(time(date))" }

    public func range(_ start: Date, _ end: Date) -> String {
        if calendar.isDate(start, inSameDayAs: end) { return "\(day(start)), \(time(start))–\(time(end))" }
        return "\(dateTime(start)) – \(dateTime(end))"
    }

    /// Local midnight of the day `date` falls on, moved by whole days.
    public func startOfDay(_ date: Date, addingDays days: Int = 0) -> Date {
        let start = calendar.startOfDay(for: date)
        return days == 0 ? start : calendar.date(byAdding: .day, value: days, to: start)!
    }

    public func iso(_ date: Date) -> String { ISODate.format(date, in: timeZone) }

    /// Accepts an instant ("2026-11-04T09:00:00-05:00") or a day ("2026-11-04", read as local
    /// midnight, or the end of that day when `endOfDay` is set).
    public func parse(_ text: String, endOfDay: Bool = false) -> Date? {
        if let instant = ISODate.parseInstant(text) { return instant }
        guard let d = ISODate.parseDay(text) else { return nil }
        var comps = DateComponents()
        comps.year = d.year
        comps.month = d.month
        comps.day = d.day
        guard let start = calendar.date(from: comps) else { return nil }
        return endOfDay ? calendar.date(byAdding: .day, value: 1, to: start) : start
    }
}
