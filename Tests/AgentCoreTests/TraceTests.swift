import Foundation
import Testing

@testable import AgentCore

@Suite("Trace")
struct TraceTests {
    @Test func masksPersonalDataInTraces() {
        let m = PIIMasker(names: ["Camila Herrera"])
        let out = m.mask("Escribe a c.herrera@example.edu o al +57 300 111 2233; camila herrera confirmó para 2026-11-04")
        #expect(!out.contains("example.edu"))
        #expect(!out.contains("300 111"))
        #expect(!out.lowercased().contains("camila herrera"))
        #expect(out.contains("[C. H.]"))
        #expect(out.contains("2026-11-04"))
    }

    @Test func pricesOnlyCloudCallsButKeepsAReference() {
        let usage = TokenUsage(input: 1_000_000, output: 100_000)
        let book = PriceBook.claude2026
        #expect(book.cost(model: "apple-on-device", tier: .onDevice, usage: usage) == 0)
        #expect(abs(book.cost(model: "claude-sonnet-5-5", tier: .claude, usage: usage) - 3.0) < 1e-9)
        #expect(abs(book.referenceCost(usage) - 3.0) < 1e-9)
    }

    @Test func jsonRoundTrips() throws {
        let v: JSONValue = ["a": [1, 2.5, "x", true, nil], "b": ["c": "d"]]
        #expect(try JSONValue.parse(v.jsonString()) == v)
    }
}
