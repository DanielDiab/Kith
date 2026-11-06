import Foundation

/// Clock times the person stated in their message: "de 7 a 8", "a las 10:30", "7 pm",
/// "from 9 to 10". A proposed event is checked against them before it is held, so a model
/// that turns "de 7 a 8" into 07:00–09:00 is told to fix it instead of putting the wrong
/// event on the confirmation card.
struct StatedTimes: Equatable {
    struct Time: Equatable {
        var hour: Int
        var minute: Int
        /// "7" without am/pm could be 07:00 or 19:00.
        var ambiguous: Bool

        func matches(hour h: Int, minute m: Int) -> Bool {
            guard m == minute else { return false }
            return h == hour || (ambiguous && hour < 12 && h == hour + 12)
        }

        var label: String {
            let base = String(format: "%02d:%02d", hour, minute)
            return ambiguous && hour < 12 ? "\(base) (or \(String(format: "%02d:%02d", hour + 12, minute)))" : base
        }
    }

    /// "de 7 a 8": both ends.
    var range: (start: Time, end: Time)?
    /// Every other time mentioned ("a las 7", "10:30").
    var times: [Time] = []

    var isEmpty: Bool { range == nil && times.isEmpty }

    /// Days the person named, as offsets from today: "hoy" 0, "mañana" 1, "el viernes" from a
    /// Wednesday 2. A weekday that is today could mean today or a week later, so both count.
    static func days(in message: String, today weekday: Int) -> Set<Int> {
        let text = " " + message.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .map { $0.isLetter ? $0 : " " } + " "
        var out: Set<Int> = []
        if text.contains(" pasado manana ") { out.insert(2) } else if text.contains(" manana ") || text.contains(" tomorrow ") { out.insert(1) }
        if text.contains(" hoy ") || text.contains(" today ") || text.contains(" tonight ") || text.contains(" esta noche ") { out.insert(0) }
        // Calendar weekday numbers: Sunday 1 … Saturday 7.
        let names: [(Int, [String])] = [
            (1, ["domingo", "sunday"]), (2, ["lunes", "monday"]), (3, ["martes", "tuesday"]), (4, ["miercoles", "wednesday"]),
            (5, ["jueves", "thursday"]), (6, ["viernes", "friday"]), (7, ["sabado", "saturday"]),
        ]
        for (n, words) in names where words.contains(where: { text.contains(" \($0) ") }) {
            let ahead = (n - weekday + 7) % 7
            out.insert(ahead)
            if ahead == 0 { out.insert(7) }
        }
        return out
    }

    static func == (a: StatedTimes, b: StatedTimes) -> Bool {
        a.times == b.times && a.range?.start == b.range?.start && a.range?.end == b.range?.end
    }

    static let clock = #"(\d{1,2})(?:[:h](\d{2}))?\s*(a\.?\s?m\.?|p\.?\s?m\.?)?"#

    static func parse(_ message: String) -> StatedTimes {
        let text = message.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var out = StatedTimes()
        let rangePattern = #"\b(?:de|desde|from|entre|between)\s+(?:las?\s+)?"# + clock
            + #"\s*(?:a|hasta|to|y|and|-)\s*(?:las?\s+)?"# + clock + #"(?!\d)"#
        if let m = text.firstMatch(of: try! Regex(rangePattern)),
           let start = time(m, 1), var end = time(m, 4) {
            // "de 7 a 8 pm": the meridiem written once applies to both ends.
            var start = start
            if start.ambiguous, !end.ambiguous, end.hour >= 12, start.hour < 12, start.hour + 12 <= end.hour {
                start.hour += 12
                start.ambiguous = false
            }
            if end.ambiguous, !start.ambiguous, start.hour >= 12, end.hour < 12 { end.hour += 12; end.ambiguous = false }
            out.range = (start, end)
            return out
        }
        let single = [
            #"\b(?:a\s+las?|a\s+la|at|desde\s+las?)\s+"# + clock + #"(?!\d)"#,
            #"\b(\d{1,2}):(\d{2})\s*(a\.?\s?m\.?|p\.?\s?m\.?)?"#,
            #"\b(\d{1,2})()\s*(a\.?\s?m\.?|p\.?\s?m\.?)(?=\W|$)"#,
        ]
        for p in single {
            for m in text.matches(of: try! Regex(p)) {
                if let t = time(m, 1), !out.times.contains(t) { out.times.append(t) }
            }
        }
        return out
    }

    /// Reads hour, minute and meridiem from three capture groups starting at `first`.
    private static func time(_ m: Regex<AnyRegexOutput>.Match, _ first: Int) -> Time? {
        func group(_ i: Int) -> String? { m.output[i].substring.map(String.init).flatMap { $0.isEmpty ? nil : $0 } }
        guard let h = group(first).flatMap(Int.init) else { return nil }
        let minute = group(first + 1).flatMap(Int.init) ?? 0
        guard (0...23).contains(h), (0...59).contains(minute) else { return nil }
        let marker = group(first + 2)?.filter(\.isLetter) ?? ""
        var hour = h
        if marker == "pm", hour < 12 { hour += 12 }
        if marker == "am", hour == 12 { hour = 0 }
        return Time(hour: hour, minute: minute, ambiguous: marker.isEmpty && hour <= 12)
    }
}
