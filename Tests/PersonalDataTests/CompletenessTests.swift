import AgentCore
import Foundation
import Testing

@testable import PersonalData

/// Answers that pass the output guard but leave the request unfinished: what the on-device
/// model did in its first real-model run ("No tengo la duración…" without reading the
/// calendar, "¿Quieres que lo marque?" instead of proposing the change).
@Suite("Completeness")
struct CompletenessTests {
    @Test func nudgesAnAnswerGivenWithoutReadingTheData() async throws {
        let model = ScriptedBackend(attempts: [
            [.init(answer: "No tengo la duración de esa cita.")],
            [.init(call: "calendar_list_events", args: today), .init(answer: "La cita del odontólogo dura 45 minutos.")],
        ])
        let h = try await Harness(backends: [model])
        let turn = await h.agent.respond(to: "¿Cuánto dura la cita del odontólogo?")
        #expect(turn.outcome == .answered)
        #expect(turn.reply.contains("45"))
        #expect(turn.calledTools == ["calendar_list_events"])
        #expect(turn.trace.spans.contains { $0.name == "completeness" && $0.status == .failed })
        let nudge = try #require(await model.requests.last?.messages.last?.content)
        #expect(nudge.hasPrefix("[Platform] You answered without reading"))
    }

    @Test func nudgesARequestedChangeThatWasNotProposed() async throws {
        let model = ScriptedBackend(attempts: [
            [.init(call: "reminders_list"), .init(answer: "¿Quieres que lo marque como hecho?")],
            [.init(call: "reminders_complete", args: ["title": "pasaporte"]), .init(answer: "Queda pendiente de tu confirmación.")],
        ])
        let h = try await Harness(backends: [model])
        let turn = await h.agent.respond(to: "Marca como hecho el recordatorio de renovar el pasaporte")
        #expect(turn.outcome == .awaitingConfirmation)
        let held = try #require(turn.heldWrites.first)
        #expect(held.arguments == ["id": "rem-204"])
        #expect(held.summary == "Mark “Renovar pasaporte” as done")
        #expect(await h.store.writeLog.isEmpty)
    }

    @Test func keepsATrueAnswerWhenNoTierFinishesTheRequest() async throws {
        let model = ScriptedBackend(steps: [.init(answer: "¿A qué hora quieres el gimnasio?")])
        let h = try await Harness(backends: [model], privacy: .deviceOnly)
        let turn = await h.agent.respond(to: "Agéndame gimnasio el viernes")
        #expect(turn.outcome == .answered)
        #expect(turn.reply == "¿A qué hora quieres el gimnasio?")
        #expect(await model.requestCount() == 2)
    }

    @Test func answersSmallTalkWithoutTools() async throws {
        let model = ScriptedBackend(steps: [.init(answer: "¡Hola! ¿En qué te ayudo?")])
        let h = try await Harness(backends: [model])
        let turn = await h.agent.respond(to: "¡Hola, gracias!")
        #expect(turn.outcome == .answered)
        #expect(await model.requestCount() == 1)
    }

    @Test func acceptsARefusalWhenTheGateDeniedTheTool() async throws {
        let model = ScriptedBackend(steps: [
            .init(call: "reminders_complete", args: ["id": "rem-201"]),
            .init(answer: "No puedo hacer cambios desde aquí."),
        ])
        let h = try await Harness(backends: [model])
        let turn = await h.agent.respond(to: "¿Qué recordatorios tengo?")
        #expect(turn.outcome == .answered)
        #expect(await model.requestCount() == 1)
    }

    @Test func refusesADoneClaimAfterAHeldWrite() async throws {
        let model = ScriptedBackend(steps: [
            .init(call: "reminders_complete", args: ["title": "pasaporte"]),
            .init(answer: "El recordatorio está marcado como hecho, pero espera confirmación."),
        ])
        let h = try await Harness(backends: [model], privacy: .deviceOnly)
        let turn = await h.agent.respond(to: "Marca como hecho el recordatorio de renovar el pasaporte")
        #expect(turn.outcome == .failedSafe)
        #expect(turn.unverifiedClaims.map(\.kind) == [.writeWithoutAction])
        #expect(await h.store.writeLog.isEmpty)
    }
}

@Suite("Tools for small models")
struct SmallModelToolTests {
    let format = LocalFormat(timeZone: SyntheticData.timeZone)

    @Test func listsTheComingWeekWhenTheRangeIsLeftOut() async throws {
        let tool = ListEvents(store: SyntheticData.store(), format: format, now: { SyntheticData.now })
        let week = try await tool.call([:])
        #expect(week["count"]?.intValue == 6)  // Wed 4 through Tue 10, not Monday's or Tuesday's past events
        let fromFriday = try await tool.call(["from": "2026-11-06", "to": "2026-11-08"])
        #expect(fromFriday["events"]?.arrayValue?.first?["title"]?.stringValue == "Almuerzo con Mateo")
    }

    @Test func resolvesAReminderByTitleBeforeItIsHeld() async throws {
        let tool = CompleteReminder(store: SyntheticData.store(), format: format)
        #expect(try await tool.resolve(["title": "el pasaporte"], personSaid: "") == ["id": "rem-204"])
        #expect(try await tool.resolve(["title": "Pagar tarjeta"], personSaid: "") == ["id": "rem-201"])
        #expect(try await tool.resolve(["id": "rem-203"], personSaid: "") == ["id": "rem-203"])
    }

    @Test func refusesTitlesThatNameNoneOrSeveral() async throws {
        let store = SyntheticData.store()
        await store.add(reminder: Reminder(id: "rem-777", title: "Renovar pasaporte de Laura"))
        let tool = CompleteReminder(store: store, format: format)
        await #expect(throws: ToolError.self) { try await tool.resolve(["title": "pasaporte"], personSaid: "") }
        await #expect(throws: ToolError.self) { try await tool.resolve(["title": "vacuna del perro"], personSaid: "") }
        await #expect(throws: ToolError.self) { try await tool.resolve(["id": "rem-000"], personSaid: "") }
        // A completed reminder can't be completed again.
        await #expect(throws: ToolError.self) { try await tool.resolve(["title": "capítulo 4 DDIA"], personSaid: "") }
    }
}

/// A proposed event must use the times the person said: the on-device model once turned
/// "de 7 a 8" into 07:00–09:00.
@Suite("Write binding")
struct WriteBindingTests {
    let tool = CreateEvent(store: SyntheticData.store(), format: LocalFormat(timeZone: SyntheticData.timeZone), now: { SyntheticData.now })

    func event(_ start: String, _ end: String) -> JSONValue {
        ["title": "Gimnasio", "start": .string("2026-11-06T\(start):00-05:00"), "end": .string("2026-11-06T\(end):00-05:00")]
    }

    @Test func readsTheTimesThePersonSaid() {
        let range = StatedTimes.parse("Agéndame gimnasio el viernes de 7 a 8").range
        #expect(range?.start == .init(hour: 7, minute: 0, ambiguous: true))
        #expect(range?.end == .init(hour: 8, minute: 0, ambiguous: true))
        let pm = StatedTimes.parse("cena de 7 a 9 pm").range
        #expect(pm?.start.hour == 19 && pm?.end.hour == 21)
        #expect(StatedTimes.parse("from 9:30 to 10:15").range?.end == .init(hour: 10, minute: 15, ambiguous: true))
        #expect(StatedTimes.parse("ponme una cita a las 10:30").times == [.init(hour: 10, minute: 30, ambiguous: true)])
        #expect(StatedTimes.parse("call at 3pm").times == [.init(hour: 15, minute: 0, ambiguous: false)])
        #expect(StatedTimes.parse("Agéndame gimnasio el viernes").isEmpty)
        #expect(StatedTimes.parse("el 2026-11-06").isEmpty)
    }

    @Test func holdsAnEventAtTheStatedTimes() async throws {
        let said = "Agéndame gimnasio el viernes de 7 a 8"
        _ = try await tool.resolve(event("07:00", "08:00"), personSaid: said)
        _ = try await tool.resolve(event("19:00", "20:00"), personSaid: said)
        _ = try await tool.resolve(event("10:30", "11:30"), personSaid: "una cita a las 10:30")
        _ = try await tool.resolve(event("06:00", "07:00"), personSaid: "")  // MCP: arguments are explicit
    }

    @Test func refusesAnEventAtOtherTimes() async throws {
        let said = "Agéndame gimnasio el viernes de 7 a 8"
        await #expect(throws: ToolError.self) { try await tool.resolve(event("07:00", "09:00"), personSaid: said) }
        await #expect(throws: ToolError.self) { try await tool.resolve(event("08:00", "09:00"), personSaid: said) }
        await #expect(throws: ToolError.self) { try await tool.resolve(event("07:00", "08:00"), personSaid: "cena de 7 a 8 pm") }
        await #expect(throws: ToolError.self) { try await tool.resolve(event("11:00", "12:00"), personSaid: "una cita a las 10:30") }
    }

    @Test func readsTheDayThePersonSaid() {
        // Wednesday is weekday 4.
        #expect(StatedTimes.days(in: "Agéndame gimnasio el viernes de 7 a 8", today: 4) == [2])
        #expect(StatedTimes.days(in: "cita mañana a las 9", today: 4) == [1])
        #expect(StatedTimes.days(in: "pasado mañana", today: 4) == [2])
        #expect(StatedTimes.days(in: "dinner on Wednesday", today: 4) == [0, 7])
        #expect(StatedTimes.days(in: "el lunes", today: 4) == [5])
        #expect(StatedTimes.days(in: "a las 7", today: 4).isEmpty)
    }

    @Test func refusesAnEventOnAnotherDay() async throws {
        // Qwen 8B once held "el viernes de 7 a 8" on Thursday.
        let thursday: JSONValue = ["title": "Gimnasio", "start": "2026-11-05T07:00:00-05:00", "end": "2026-11-05T08:00:00-05:00"]
        await #expect(throws: ToolError.self) { try await tool.resolve(thursday, personSaid: "Agéndame gimnasio el viernes de 7 a 8") }
        _ = try await tool.resolve(event("07:00", "08:00"), personSaid: "Agéndame gimnasio el viernes de 7 a 8")
    }

    @Test func tellsTheModelWhichTimesToUse() async throws {
        let model = ScriptedBackend(steps: [
            .init(call: "calendar_create_event", args: event("07:00", "09:00")),
            .init(call: "calendar_create_event", args: event("07:00", "08:00")),
            .init(answer: "Propuse Gimnasio el vie 6 nov 2026, 07:00–08:00; falta tu confirmación."),
        ])
        let h = try await Harness(backends: [model])
        let turn = await h.agent.respond(to: "Agéndame gimnasio el viernes de 7 a 8")
        #expect(turn.outcome == .awaitingConfirmation)
        #expect(turn.heldWrites.count == 1)
        #expect(turn.heldWrites.first?.summary == "Create “Gimnasio” · vie 6 nov 2026, 07:00–08:00")
    }
}

@Suite("Computed for the model")
struct ComputedTests {
    @Test func listsOverlappingEvents() async throws {
        let tool = ListEvents(store: SyntheticData.store(), format: LocalFormat(timeZone: SyntheticData.timeZone))
        let result = try await tool.call(today)
        let overlaps = try #require(result["overlaps"]?.arrayValue)
        #expect(overlaps.count == 1)
        #expect(overlaps[0]["events"] == ["Proyecto de grado: revisión con Camila Herrera", "Entrevista técnica"])
        #expect(overlaps[0]["overlap_local"]?.stringValue == "mié 4 nov 2026, 15:00–15:30")
        let friday = try await tool.call(["from": "2026-11-06", "to": "2026-11-06"])
        #expect(friday["overlaps"]?.arrayValue?.isEmpty == true)
    }

    @Test func holdsTheSameChangeOnce() async throws {
        let model = ScriptedBackend(steps: [
            .init(call: "reminders_complete", args: ["title": "pasaporte"]),
            .init(call: "reminders_complete", args: ["id": "rem-204"]),
            .init(answer: "Queda pendiente de tu confirmación en la app."),
        ])
        let h = try await Harness(backends: [model])
        let turn = await h.agent.respond(to: "Marca como hecho el recordatorio de renovar el pasaporte")
        #expect(turn.heldWrites.count == 1)
        #expect(await h.agent.pendingWrites().count == 1)
    }
}

@Suite("Held changes are announced")
struct AnnouncedTests {
    @Test func asksAgainWhenTheReplyHidesAHeldChange() async throws {
        let event: JSONValue = [
            "title": "Gimnasio", "start": "2026-11-06T07:00:00-05:00", "end": "2026-11-06T08:00:00-05:00",
        ]
        let model = ScriptedBackend(attempts: [
            [.init(call: "calendar_create_event", args: event), .init(answer: "No hay eventos el viernes de 07:00 a 08:00.")],
            [.init(answer: "Propuse Gimnasio el viernes de 07:00 a 08:00; confírmalo en la app.")],
        ])
        let h = try await Harness(backends: [model])
        let turn = await h.agent.respond(to: "Agéndame gimnasio el viernes de 7 a 8")
        #expect(turn.outcome == .awaitingConfirmation)
        #expect(turn.reply.contains("confírmalo"))
        #expect(turn.heldWrites.count == 1)
    }

    @Test func readsOneDayWhenOnlyTheStartIsGiven() async throws {
        let tool = ListEvents(store: SyntheticData.store(), format: LocalFormat(timeZone: SyntheticData.timeZone))
        let thursday = try await tool.call(["from": "2026-11-05"])
        #expect(thursday["events"]?.arrayValue?.compactMap { $0["title"]?.stringValue } == ["Gimnasio"])
    }
}
