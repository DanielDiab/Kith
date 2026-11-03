import Foundation
import Testing

@testable import AgentCore

@Suite("Router")
struct RouterTests {
    let profiles = [
        TierProfile(tier: .onDevice, model: "apple-on-device", contextTokens: 4_096),
        TierProfile(tier: .localOpen, model: "qwen3:8b", contextTokens: 32_768),
        TierProfile(tier: .claude, model: "claude-sonnet-5-5", contextTokens: 200_000),
    ]

    @Test func keepsSimpleRequestsOnDevice() throws {
        let d = try #require(Router(profiles: profiles).route(promptTokens: 800, userText: "¿Qué tengo mañana?", privacy: .allowCloud))
        #expect(d.tier == .onDevice)
    }

    @Test func sendsMultiStepRequestsToTheMac() throws {
        let d = try #require(Router(profiles: profiles).route(
            promptTokens: 800, userText: "Organiza mi semana y dime si hay conflictos", privacy: .allowCloud))
        #expect(d.tier == .localOpen)
        #expect(d.skipped["onDevice"] != nil)
    }

    @Test func respectsPrivacyMode() throws {
        let unavailableLocal = profiles.map { p -> TierProfile in
            var p = p
            if p.tier == .localOpen { p.available = false }
            return p
        }
        let r = Router(profiles: unavailableLocal)
        let cloud = try #require(r.route(promptTokens: 800, userText: "Compara mis dos próximas semanas", privacy: .allowCloud))
        #expect(cloud.tier == .claude)
        let own = try #require(r.route(promptTokens: 800, userText: "Compara mis dos próximas semanas", privacy: .ownHardware))
        #expect(own.tier == .onDevice)
        #expect(own.reason.contains("no tier fits"))
    }

    @Test func movesUpWhenThePromptDoesNotFit() throws {
        let d = try #require(Router(profiles: profiles).route(promptTokens: 6_000, userText: "¿Qué tengo hoy?", privacy: .allowCloud))
        #expect(d.tier == .localOpen)
        #expect(d.skipped["onDevice"]?.contains("context") == true)
    }

    @Test func escalatesAboveAFloor() throws {
        let d = try #require(Router(profiles: profiles).route(
            promptTokens: 800, userText: "¿Qué tengo hoy?", privacy: .allowCloud, startingAbove: .onDevice))
        #expect(d.tier == .localOpen)
        #expect(Router(profiles: profiles).route(promptTokens: 800, userText: "hoy", privacy: .ownHardware, startingAbove: .localOpen) == nil)
    }
}
