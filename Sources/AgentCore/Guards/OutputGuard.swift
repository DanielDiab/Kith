import Foundation

/// What the answer may rely on: every tool result of this turn, plus what the person said.
public struct Evidence: Sendable {
    public var toolResults: [JSONValue]
    public var userText: String

    public init(toolResults: [JSONValue] = [], userText: String = "") {
        self.toolResults = toolResults
        self.userText = userText
    }
}

public struct OutputVerdict: Sendable, Equatable {
    public var unverified: [Claim]
    public var checkedClaims: Int
    public var passed: Bool { unverified.isEmpty }
}

/// Checks that dates, times, figures and names in an answer come from tool results.
///
/// This is Charter's figure guard, extended for personal data. Three rules carry most of
/// the weight:
///
/// - **Figures are compared with their unit.** Charter compared values only, so a correct
///   number in the wrong unit passed. Here 45 min and 45 h are different facts, and 90 min
///   still matches 1.5 h.
/// - **Times are compared as instants in the person's time zone.** A tool returns
///   `2026-11-04T15:00:00Z`; in Bogotá that is 10:00. An answer that says "15:00" read the
///   UTC string and is wrong, even though "15:00" appears in the data. Same lesson as units:
///   compare what the value means, not how it is spelled.
/// - **Names come from data.** A contact's name in the answer must appear in this turn's
///   tool results or in the person's own message.
public struct OutputGuard: Sendable {
    public var timeZone: TimeZone
    /// Every contact name the store knows about. A name from this list in an answer has to
    /// be backed by the evidence.
    public var knownNames: [String]

    public init(timeZone: TimeZone, knownNames: [String] = []) {
        self.timeZone = timeZone
        self.knownNames = knownNames
    }

    public func check(_ answer: String, evidence: Evidence) -> OutputVerdict {
        let index = EvidenceIndex(evidence, timeZone: timeZone)
        let folded = Text.fold(answer)
        let facts = FactExtractor.extract(fromFolded: folded)
        var unverified: [Claim] = []
        var checked = 0

        for t in facts.times {
            checked += 1
            if !index.hasTime(t) { unverified.append(Claim(kind: .time, text: t.text)) }
        }
        for d in facts.dates {
            checked += 1
            if !index.hasDate(d) { unverified.append(Claim(kind: .date, text: d.text)) }
        }
        for q in facts.quantities {
            checked += 1
            if !index.hasQuantity(q) { unverified.append(Claim(kind: q.isCount ? .count : .quantity, text: q.text)) }
        }
        for name in knownNames {
            let n = Text.fold(name)
            guard n.count >= 3, folded.contains(n) else { continue }
            checked += 1
            if !index.foldedText.contains(n) { unverified.append(Claim(kind: .name, text: name)) }
        }
        for m in Text.matches(#"[“"«]([^”"»\n]{3,80})[”"»]"#, in: answer) {
            guard let inner = m.groups[0] else { continue }
            checked += 1
            if !index.foldedText.contains(Text.fold(inner).trimmingCharacters(in: .whitespaces)) {
                unverified.append(Claim(kind: .quotedTitle, text: inner))
            }
        }
        for claim in Self.writeClaims(inFolded: folded) {
            checked += 1
            unverified.append(Claim(kind: .writeWithoutAction, text: claim))
        }
        return OutputVerdict(unverified: unverified, checkedClaims: checked)
    }

    /// "Quedó agendado", "I've added it": inside a turn every write is still held, so any
    /// claim that one happened is false. Negated forms ("no se ha creado") are skipped.
    static func writeClaims(inFolded text: String) -> [String] {
        // Narrow on purpose: "la reunión está programada para las 10" describes data the
        // agent read, so plain "está"/"was" + participle is not treated as a claim.
        let participles =
            "(?:guardad|registrad|cread|agendad|programad|completad|marcad|anadid|agregad|apuntad)[oa]s?"
        let patterns = [
            #"\b(?:quedo|ha\s+quedado|quedaron|han\s+quedado|ha\s+sido|han\s+sido)\s+(?:correctamente\s+|exitosamente\s+)?"# + participles + #"\b"#,
            #"\b(?:he|hemos|se\s+ha|se\s+han|ya\s+he|ya\s+hemos)\s+(?:guardado|registrado|creado|agendado|programado|completado|marcado|anadido|agregado|apuntado)\b"#,
            #"\b(?:i've|i\s+have|we've|we\s+have|i)\s+(?:just\s+|successfully\s+)?(?:created|added|scheduled|saved|marked|completed|booked)\b"#,
            #"\b(?:has|have)\s+been\s+(?:successfully\s+)?(?:created|added|saved|booked)\b"#,
        ]
        var out: [String] = []
        for p in patterns {
            for m in Text.matches(p, in: text) {
                let before = text[text.startIndex..<m.range.lowerBound].suffix(5)
                if before.hasSuffix("no ") || before.hasSuffix("not ") || before.hasSuffix("n't ") { continue }
                out.append(m.text)
            }
        }
        return out
    }
}

// MARK: - Evidence index

struct EvidenceIndex {
    struct LocalTime: Hashable { var hour: Int; var minute: Int }
    struct LocalDate: Hashable { var year: Int; var month: Int; var day: Int }

    var quantities: [Quantity] = []
    var times: Set<LocalTime> = []
    var dates: Set<LocalDate> = []
    var foldedText = ""

    init(_ evidence: Evidence, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var texts: [String] = []
        var qs: [Quantity] = []
        var ts: Set<LocalTime> = []
        var ds: Set<LocalDate> = []

        func addInstant(_ date: Date) {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            ts.insert(LocalTime(hour: c.hour ?? -1, minute: c.minute ?? -1))
            ds.insert(LocalDate(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0))
        }

        func addText(_ s: String) {
            let folded = Text.fold(s)
            texts.append(folded)
            let facts = FactExtractor.extract(fromFolded: folded)
            for t in facts.times {
                ts.insert(LocalTime(hour: t.hour, minute: t.minute))
                if t.ambiguous12h, t.hour < 12 { ts.insert(LocalTime(hour: t.hour + 12, minute: t.minute)) }
            }
            for d in facts.dates {
                ds.insert(LocalDate(year: d.year ?? 0, month: d.month, day: d.day))
            }
            for q in facts.quantities {
                for v in q.values { qs.append(Quantity(value: v * q.multiplier, unit: q.unit)) }
            }
        }

        func walk(_ value: JSONValue, path: String) {
            switch value {
            case .number(let n):
                qs.append(Quantity(value: n, unit: FactUnit.fromKey(path)))
            case .string(let s):
                if let instant = ISODate.parseInstant(s) {
                    addInstant(instant)
                } else if let day = ISODate.parseDay(s) {
                    ds.insert(LocalDate(year: day.year, month: day.month, day: day.day))
                } else {
                    addText(s)
                }
            case .array(let items):
                qs.append(Quantity(value: Double(items.count), unit: .count))
                for (i, item) in items.enumerated() { walk(item, path: "\(path)[\(i)]") }
            case .object(let fields):
                if let s = fields["start"]?.stringValue.flatMap(ISODate.parseInstant),
                   let e = fields["end"]?.stringValue.flatMap(ISODate.parseInstant) {
                    qs.append(Quantity(value: e.timeIntervalSince(s) / 60, unit: .minute))
                }
                for key in fields.keys.sorted() {
                    walk(fields[key]!, path: path.isEmpty ? key : "\(path).\(key)")
                }
            case .bool, .null:
                break
            }
        }

        for result in evidence.toolResults { walk(result, path: "") }
        addText(evidence.userText)
        quantities = qs
        times = ts
        dates = ds
        foldedText = texts.joined(separator: "\n")
    }

    func hasTime(_ t: TimeClaim) -> Bool {
        if times.contains(LocalTime(hour: t.hour, minute: t.minute)) { return true }
        if t.ambiguous12h {
            let other = t.hour == 12 ? 0 : (t.hour < 12 ? t.hour + 12 : t.hour - 12)
            return times.contains(LocalTime(hour: other, minute: t.minute))
        }
        return false
    }

    func hasDate(_ d: DateClaim) -> Bool {
        dates.contains { $0.month == d.month && $0.day == d.day && (d.year == nil || $0.year == 0 || $0.year == d.year) }
    }

    func hasQuantity(_ q: QuantityClaim) -> Bool {
        quantities.contains { ev in Self.matches(q, ev) }
    }

    /// Value rules, loosest to strictest, as in Charter:
    /// - written as a rounded scale ("1,5 millones"): 0.5 % relative tolerance;
    /// - a short integer ("78 %"): the data rounded to an integer;
    /// - with decimals ("871,6"): the data rounded to that many decimals;
    /// - a full amount ("4.833.195"): exact.
    /// Unit rules: a count only matches a count; two known units must share a dimension and
    /// are converted before comparing; a missing unit on either side compares the value alone.
    static func matches(_ q: QuantityClaim, _ ev: Quantity) -> Bool {
        if q.isCount, ev.unit != .count { return false }
        var evValue = ev.value
        if let cu = q.unit, let eu = ev.unit {
            guard cu.isCompatible(with: eu) else { return false }
            evValue = ev.value * eu.factor / cu.factor
        }
        let digits = q.token.filter(\.isNumber).drop { $0 == "0" }
        let decimals: Int? = Text.matches(#"[.,](\d{1,2})$"#, in: q.token).first?.groups[0].map { $0.count }
        for v in q.values {
            let claimed = v * q.multiplier
            if abs(claimed - evValue) < 1e-9 { return true }
            if q.multiplier > 1, evValue != 0, abs(claimed - evValue) / abs(evValue) <= 0.005 { return true }
            if decimals == nil, digits.count <= 3, abs(claimed - evValue.rounded()) < 1e-9 { return true }
            if let k = decimals {
                let p = pow(10.0, Double(k))
                if abs(claimed - (evValue * p).rounded() / p) < 1e-9 { return true }
            }
        }
        return false
    }
}

/// ISO 8601 helpers. Tools return instants with the person's offset
/// ("2026-11-04T10:00:00-05:00") so the model doesn't have to convert time zones.
public enum ISODate {
    public static func parseInstant(_ s: String) -> Date? {
        guard s.count >= 19, s.first?.isNumber == true, s.contains("T") else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    public static func parseDay(_ s: String) -> (year: Int, month: Int, day: Int)? {
        let parts = s.split(separator: "-")
        guard s.count == 10, parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            return nil
        }
        return (y, m, d)
    }

    public static func format(_ date: Date, in timeZone: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = timeZone
        return f.string(from: date)
    }
}
