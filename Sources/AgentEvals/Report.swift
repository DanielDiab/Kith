import Foundation

/// The numbers that go in the README and on the portfolio.
public struct Report: Codable, Sendable {
    public var generatedAt: String
    public var suites: [SuiteResult]

    enum CodingKeys: String, CodingKey { case generatedAt = "generated_at", suites }

    public init(generatedAt: Date = Date(), suites: [SuiteResult]) {
        let f = ISO8601DateFormatter()
        self.generatedAt = f.string(from: generatedAt)
        self.suites = suites
    }

    public var allMeetThreshold: Bool { suites.allSatisfy(\.meetsThreshold) }

    public func json() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    public func markdown() -> String {
        var lines = [
            "| Suite | Kind | Passed | Pass rate | Threshold | Gate |",
            "|---|---|---|---|---|---|",
        ]
        for s in suites {
            let rate = String(format: "%.0f %%", s.passRate * 100)
            let threshold = String(format: "%.0f %%", s.threshold * 100)
            lines.append("| \(s.name) | \(s.kind.rawValue) | \(s.passed)/\(s.total) | \(rate) | \(threshold) | \(s.meetsThreshold ? "pass" : "FAIL") |")
        }
        let failing = suites.flatMap { s in s.cases.filter { !$0.passed }.map { "- `\(s.name)/\($0.id)`: \($0.failures.joined(separator: "; "))" } }
        if !failing.isEmpty {
            lines.append("")
            lines.append("Failing cases:")
            lines.append(contentsOf: failing)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
