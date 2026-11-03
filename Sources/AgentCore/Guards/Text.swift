import Foundation

/// Small text helpers shared by the guards. Patterns are compiled on use: `Regex` is not
/// `Sendable`, and these guards run a handful of patterns per turn, so caching buys nothing.
enum Text {
    /// Lowercased, Spanish accents removed. "Ignóra las INSTRUCCIONES" → "ignora las instrucciones".
    static func fold(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.lowercased() {
            switch ch {
            case "á", "à", "ä", "â": out.append("a")
            case "é", "è", "ë", "ê": out.append("e")
            case "í", "ì", "ï", "î": out.append("i")
            case "ó", "ò", "ö", "ô": out.append("o")
            case "ú", "ù", "ü", "û": out.append("u")
            case "ñ": out.append("n")
            case "’", "‘": out.append("'")
            case "“", "”": out.append("\"")
            default: out.append(ch)
            }
        }
        return out
    }

    /// First match of `pattern` in `text`, or nil. Invalid patterns are a programming error.
    static func firstMatch(_ pattern: String, in text: String) -> String? {
        let regex: Regex<AnyRegexOutput>
        do { regex = try Regex(pattern) } catch { preconditionFailure("Invalid pattern \(pattern): \(error)") }
        guard let match = text.firstMatch(of: regex) else { return nil }
        return String(text[match.range])
    }

    /// Every match of `pattern`, with its range, its text and its numbered capture groups.
    static func matches(_ pattern: String, in text: String) -> [(range: Range<String.Index>, text: String, groups: [String?])] {
        let regex: Regex<AnyRegexOutput>
        do { regex = try Regex(pattern) } catch { preconditionFailure("Invalid pattern \(pattern): \(error)") }
        return text.matches(of: regex).map { match in
            var groups: [String?] = []
            if match.output.count > 1 {
                for i in 1..<match.output.count {
                    groups.append(match.output[i].substring.map(String.init))
                }
            }
            return (match.range, String(text[match.range]), groups)
        }
    }

    /// Replaces the given ranges with spaces of the same character count, so other
    /// extractors don't read the same digits twice.
    static func blank(_ ranges: [Range<String.Index>], in text: String) -> String {
        var result = text
        for r in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            let length = text[r].count
            result.replaceSubrange(r, with: String(repeating: " ", count: length))
        }
        return result
    }
}
