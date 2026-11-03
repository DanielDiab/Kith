import Foundation

/// Masks personal data before a trace is stored or exported. The answer the person sees is
/// never masked (it's their own data); the trace is, because traces get shared, attached to
/// bug reports and published as eval results.
public struct PIIMasker: Sendable {
    /// Contact names to mask, longest first so "Ana María Gómez" wins over "Ana María".
    public var names: [String]

    public init(names: [String] = []) {
        self.names = names.filter { $0.count >= 3 }.sorted { $0.count > $1.count }
    }

    public func mask(_ text: String) -> String {
        var out = text
        out = replace(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: out, with: "[email]")
        // Phone shapes only: +57 300 123 4567, 300-123-4567, 3001234567. A looser pattern
        // would eat ISO dates ("2026-11-04") and make the trace unreadable.
        out = replace(#"\+\d{1,3}[\s-]?\d{2,4}[\s-]?\d{3,4}[\s-]?\d{3,4}"#, in: out, with: "[phone]")
        out = replace(#"\b\d{3}[\s.-]\d{3}[\s.-]\d{4}\b|\b3\d{9}\b"#, in: out, with: "[phone]")
        for name in names {
            out = out.replacingOccurrences(of: name, with: initials(name), options: [.caseInsensitive, .diacriticInsensitive])
        }
        return out
    }

    public func mask(_ value: JSONValue) -> JSONValue {
        value.mapStrings { _, s in mask(s) }
    }

    func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").compactMap(\.first).map { "\($0)." }.joined(separator: " ")
        return "[\(letters)]"
    }

    private func replace(_ pattern: String, in text: String, with replacement: String) -> String {
        let ranges = Text.matches(pattern, in: text).map(\.range)
        var out = text
        for r in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            out.replaceSubrange(r, with: replacement)
        }
        return out
    }
}
