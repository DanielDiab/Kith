import Foundation

/// Units the output guard understands. Values are compared after converting to a common
/// unit inside the same dimension (90 min = 1.5 h). A number with the wrong unit (45 h
/// when the tool said 45 min) no longer passes: that was Charter's open lesson.
public enum FactUnit: String, Codable, Sendable {
    case percent, minute, hour, day, money, usd, cop, count

    enum Dimension { case percent, duration, money, count }

    var dimension: Dimension {
        switch self {
        case .percent: return .percent
        case .minute, .hour, .day: return .duration
        case .money, .usd, .cop: return .money
        case .count: return .count
        }
    }

    /// Size of one unit in the dimension's base unit (minutes for durations).
    var factor: Double {
        switch self {
        case .hour: return 60
        case .day: return 1440
        default: return 1
        }
    }

    func isCompatible(with other: FactUnit) -> Bool {
        guard dimension == other.dimension else { return false }
        if dimension == .money, self != .money, other != .money { return self == other }
        return true
    }

    /// Unit implied by a JSON key: "duration_minutes", "progress_percent", "count".
    static func fromKey(_ path: String) -> FactUnit? {
        let key = (path.split(separator: ".").last.map(String.init) ?? path).lowercased()
        if key.hasSuffix("minutes") || key.hasSuffix("_min") { return .minute }
        if key.hasSuffix("hours") { return .hour }
        if key.hasSuffix("days") { return .day }
        if key.hasSuffix("percent") || key.hasSuffix("_pct") { return .percent }
        if key.hasSuffix("_usd") { return .usd }
        if key.hasSuffix("_cop") { return .cop }
        if key == "count" || key.hasSuffix("_count") { return .count }
        return nil
    }

    /// Unit written next to a number in text (folded: lowercase, no accents).
    static func fromWord(_ word: String) -> FactUnit? {
        let w = word.trimmingCharacters(in: .whitespaces)
        switch w {
        case "%", "por ciento", "porciento", "percent": return .percent
        case "min", "mins", "minuto", "minutos", "minute", "minutes": return .minute
        case "h", "hr", "hrs", "hora", "horas", "hour", "hours": return .hour
        case "dia", "dias", "day", "days": return .day
        case "usd", "us$", "dolares", "dollars": return .usd
        case "cop", "pesos": return .cop
        case "$": return .money
        default: return nil
        }
    }
}

public struct Quantity: Codable, Sendable, Equatable {
    public var value: Double
    public var unit: FactUnit?
}

/// Something in the answer the guard can check against the evidence.
public struct Claim: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case quantity, count, time, date, name, quotedTitle, writeWithoutAction
    }

    public var kind: Kind
    public var text: String
}

// MARK: - Extraction from text

struct TimeClaim: Equatable {
    var hour: Int
    var minute: Int
    /// "a las 3" without am/pm: either 3:00 or 15:00.
    var ambiguous12h: Bool
    var text: String
}

struct DateClaim: Equatable {
    var year: Int?
    var month: Int
    var day: Int
    var text: String
}

struct QuantityClaim: Equatable {
    var token: String
    var values: [Double]
    var multiplier: Double
    var unit: FactUnit?
    var isCount: Bool
    var text: String
}

struct ExtractedFacts {
    var times: [TimeClaim] = []
    var dates: [DateClaim] = []
    var quantities: [QuantityClaim] = []
}

enum FactExtractor {
    static let months: [(String, Int)] = [
        ("enero", 1), ("febrero", 2), ("marzo", 3), ("abril", 4), ("mayo", 5), ("junio", 6), ("julio", 7),
        ("agosto", 8), ("septiembre", 9), ("setiembre", 9), ("octubre", 10), ("noviembre", 11), ("diciembre", 12),
        ("january", 1), ("february", 2), ("march", 3), ("april", 4), ("may", 5), ("june", 6), ("july", 7),
        ("august", 8), ("september", 9), ("october", 10), ("november", 11), ("december", 12),
        ("ene", 1), ("feb", 2), ("mar", 3), ("abr", 4), ("jun", 6), ("jul", 7), ("ago", 8), ("sept", 9),
        ("sep", 9), ("oct", 10), ("nov", 11), ("dic", 12), ("jan", 1), ("apr", 4), ("aug", 8), ("dec", 12),
    ]
    static var monthAlternation: String { months.map(\.0).joined(separator: "|") }
    static func month(_ name: String) -> Int? { months.first { $0.0 == name }?.1 }

    static let countNouns =
        #"(?:eventos?|reuniones|reunion|citas?|recordatorios?|pendientes?|tareas?|contactos?|events?|meetings?|appointments?|reminders?|tasks?|contacts?|items?)"#

    /// Extracts times, dates and quantities from folded text. Each extractor blanks what it
    /// consumed, so "10:30" is read as a time and not as the numbers 10 and 30.
    static func extract(fromFolded input: String) -> ExtractedFacts {
        var facts = ExtractedFacts()
        var text = input

        // ISO dates first: 2026-11-04 (optionally with a time, which ISO parsing in evidence handles).
        var consumed: [Range<String.Index>] = []
        for m in Text.matches(#"\b(\d{4})-(\d{2})-(\d{2})\b"#, in: text) {
            if let y = Int(m.groups[0] ?? ""), let mo = Int(m.groups[1] ?? ""), let d = Int(m.groups[2] ?? "") {
                facts.dates.append(DateClaim(year: y, month: mo, day: d, text: m.text))
                consumed.append(m.range)
            }
        }
        text = Text.blank(consumed, in: text)
        consumed = []

        let monthPattern = "(\(monthAlternation))"
        // "4 de noviembre (de 2026)"
        for m in Text.matches(#"\b(\d{1,2})\s+de\s+"# + monthPattern + #"\b(?:\s+(?:de|del)\s+(\d{4}))?"#, in: text) {
            if let d = Int(m.groups[0] ?? ""), let mo = month(m.groups[1] ?? "") {
                facts.dates.append(DateClaim(year: m.groups[2].flatMap { Int($0) }, month: mo, day: d, text: m.text))
                consumed.append(m.range)
            }
        }
        text = Text.blank(consumed, in: text)
        consumed = []
        // "4 nov(.) (2026)". Before "month N", so "mar 3 nov" (martes) is not read as March 3.
        for m in Text.matches(#"\b(\d{1,2})\s+"# + monthPattern + #"\b\.?(?:\s+(\d{4}))?"#, in: text) {
            if let d = Int(m.groups[0] ?? ""), let mo = month(m.groups[1] ?? ""), d >= 1, d <= 31 {
                facts.dates.append(DateClaim(year: m.groups[2].flatMap { Int($0) }, month: mo, day: d, text: m.text))
                consumed.append(m.range)
            }
        }
        text = Text.blank(consumed, in: text)
        consumed = []

        // "November 4(th)(, 2026)" and "nov. 4"
        for m in Text.matches(monthPattern + #"\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4}))?"#, in: text) {
            if let mo = month(m.groups[0] ?? ""), let d = Int(m.groups[1] ?? ""), d >= 1, d <= 31 {
                facts.dates.append(DateClaim(year: m.groups[2].flatMap { Int($0) }, month: mo, day: d, text: m.text))
                consumed.append(m.range)
            }
        }
        text = Text.blank(consumed, in: text)
        consumed = []
        // Times. "10:30", "10:30 a. m.", "3 pm", "a las 3 (de la tarde)".
        let ampm = #"(a\.?\s?m\.?|p\.?\s?m\.?)(?=\W|$)"#
        for m in Text.matches(#"\b([01]?\d|2[0-3]):([0-5]\d)(?:\s*"# + ampm + ")?", in: text) {
            guard var h = Int(m.groups[0] ?? ""), let mi = Int(m.groups[1] ?? "") else { continue }
            let marker = m.groups[2] ?? ""
            h = applyMeridiem(h, marker)
            // "3:30" with no marker may be 3:30 or 15:30; "15:30" and "3:30 pm" are not ambiguous.
            facts.times.append(TimeClaim(hour: h, minute: mi, ambiguous12h: marker.isEmpty && (1...12).contains(h), text: m.text))
            consumed.append(m.range)
        }
        text = Text.blank(consumed, in: text)
        consumed = []
        for m in Text.matches(#"\b(1[0-2]|0?[1-9])\s*"# + ampm, in: text) {
            guard let h = Int(m.groups[0] ?? "") else { continue }
            facts.times.append(TimeClaim(hour: applyMeridiem(h, m.groups[1] ?? ""), minute: 0, ambiguous12h: false, text: m.text))
            consumed.append(m.range)
        }
        text = Text.blank(consumed, in: text)
        consumed = []
        for m in Text.matches(#"\ba\s+las?\s+(\d{1,2})\b(?:\s+de\s+la\s+(manana|tarde|noche))?"#, in: text) {
            guard var h = Int(m.groups[0] ?? ""), h <= 23 else { continue }
            let part = m.groups[1] ?? ""
            if (part == "tarde" || part == "noche") && h < 12 { h += 12 }
            facts.times.append(TimeClaim(hour: h, minute: 0, ambiguous12h: part.isEmpty && h <= 12, text: m.text))
            consumed.append(m.range)
        }
        text = Text.blank(consumed, in: text)

        facts.quantities = quantities(inFolded: text)
        return facts
    }

    static func applyMeridiem(_ hour: Int, _ marker: String) -> Int {
        let m = marker.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        if m == "pm" && hour < 12 { return hour + 12 }
        if m == "am" && hour == 12 { return 0 }
        return hour
    }

    static let numberPattern = #"\d{1,3}(?:[.,]\d{3})+(?:[.,]\d+)?|\d+(?:[.,]\d+)?"#
    static let unitAfter =
        #"\s*(%|por\s*ciento|percent|minutos?|minutes?|mins?|horas?|hours?|hrs?|h|dias?|days?|usd|us\$|dolares|dollars|cop|pesos)(?=\W|$)"#

    static func quantities(inFolded text: String) -> [QuantityClaim] {
        var out: [QuantityClaim] = []
        let pattern = #"(us\$|\$|usd\s|cop\s)?\s?("# + numberPattern + ")(?:" + unitAfter + #")?(\s+(?:mil|millones|millon|thousand|million)\b)?(\s+"# + countNouns + #"\b)?"#
        for m in Text.matches(pattern, in: text) {
            let prefix = (m.groups[0] ?? "").trimmingCharacters(in: .whitespaces)
            guard let token = m.groups[1] else { continue }
            let suffixUnit = m.groups[2].flatMap { FactUnit.fromWord($0.replacingOccurrences(of: "  ", with: " ")) }
            let scale = (m.groups[3] ?? "").trimmingCharacters(in: .whitespaces)
            let isCount = m.groups[4] != nil && suffixUnit == nil && prefix.isEmpty
            let unit: FactUnit? = isCount ? .count : (suffixUnit ?? FactUnit.fromWord(prefix))
            let multiplier: Double
            switch scale {
            case "mil", "thousand": multiplier = 1_000
            case "millones", "millon", "million": multiplier = 1_000_000
            default: multiplier = 1
            }
            let values = interpretations(token)
            guard isRelevant(token: token, unit: unit, multiplier: multiplier, isCount: isCount) else { continue }
            out.append(QuantityClaim(token: token, values: values, multiplier: multiplier, unit: unit, isCount: isCount, text: m.text.trimmingCharacters(in: .whitespaces)))
        }
        return out
    }

    /// Small bare integers ("2 options", "step 3") and years are not facts to verify.
    /// Anything with a unit, decimals, three or more digits, or a count noun is.
    static func isRelevant(token: String, unit: FactUnit?, multiplier: Double, isCount: Bool) -> Bool {
        if unit != nil || isCount || multiplier > 1 { return true }
        let digits = token.filter(\.isNumber)
        if let year = Int(digits), token.count == 4, (1900...2100).contains(year) { return false }
        if token.contains(where: { $0 == "." || $0 == "," }) { return true }
        return digits.count >= 3
    }

    /// One number, written in different conventions: 1.234,5 · 1,234.5 · 871,6 · 871.6.
    static func interpretations(_ token: String) -> [Double] {
        var values = Set<Double>()
        let clean = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        for (thousands, decimal) in [(".", ","), (",", ".")] {
            let t = clean.replacingOccurrences(of: thousands, with: "")
            if t.filter({ String($0) == decimal }).count <= 1, let v = Double(t.replacingOccurrences(of: decimal, with: ".")) {
                values.insert(v)
            }
        }
        if let v = Double(clean.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")) {
            values.insert(v)
        }
        return values.sorted()
    }
}
