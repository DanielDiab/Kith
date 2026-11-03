import Foundation

/// Finds text that tries to give the assistant instructions.
///
/// Two lists. `direct` is what a person might type to the agent. `inData` is what someone
/// plants in content the agent later reads: an event title from a calendar invite, a
/// reminder synced from a shared list, a contact note. Anyone who can send you an invite
/// can write into your calendar, so data is treated as untrusted from the start.
///
/// Patterns are the first line of defense, not the only one. The platform also refuses
/// writes that the person didn't ask for (`WriteIntent`) and holds every write for
/// confirmation, so a pattern that misses still can't make the agent act on its own.
public struct InjectionDetector: Sendable {
    public init() {}

    static let direct: [String] = [
        #"ignor\w*\s+(?:\w+\s+){0,4}(?:instrucciones|reglas|indicaciones|politicas)"#,
        #"olvid\w*\s+(?:\w+\s+){0,4}(?:instrucciones|reglas|indicaciones)"#,
        #"ignore\s+(?:all\s+|any\s+|the\s+|your\s+)?(?:previous|prior|above|earlier|system)\s+(?:instructions|rules|prompts?)"#,
        #"disregard\s+(?:all\s+|any\s+|the\s+|your\s+)?(?:previous|prior|above|system)\s+(?:instructions|rules)"#,
        #"(?:revela|muestra\w*|dime|imprime|repite|copia)\s+(?:\w+\s+){0,4}(?:prompt|instrucciones\s+de\s+sistema|tus\s+instrucciones)"#,
        #"(?:reveal|show|print|repeat|leak)\s+(?:\w+\s+){0,3}(?:system\s+prompt|instructions|hidden\s+prompt)"#,
        #"\bsystem\s+prompt\b"#,
        #"(?:act[uú]a\s+como|ahora\s+eres|finge\s+ser|you\s+are\s+now|act\s+as|pretend\s+to\s+be)\s+(?:\w+\s+){0,4}(?:sin\s+(?:reglas|restricciones|filtros)|without\s+(?:rules|restrictions|filters)|unrestricted)"#,
        #"\b(?:modo|mode)\s+(?:desarrollador|developer|dios|god|sin\s+restricciones|unrestricted)\b"#,
        #"\bjailbreak\b"#,
        #"<\|im_start\|>|<\|system\|>|\[/?inst\]|###\s*(?:system|instruction)"#,
    ]

    static let inData: [String] = [
        // Addressing the assistant from inside a field.
        #"\b(?:assistant|asistente|ai|ia|claude|siri|chatgpt|agent|agente)\s*[:,]?\s+(?:\w+\s+){0,3}(?:must|should|debe\w*|tiene\s+que|now|ahora|please|por\s+favor)\b"#,
        #"\b(?:note|nota|instruction|instruccion)\s+(?:to|for|para)\s+(?:the\s+|el\s+|la\s+)?(?:assistant|asistente|ai|ia|agent|agente|model|modelo)\b"#,
        #"\b(?:new|updated|nuevas?|actualizadas?)\s+(?:instructions|instrucciones)\b"#,
        #"\bimportant\s*[:!]\s*(?:\w+\s+){0,3}(?:assistant|ai|must|ignore)"#,
        // Asking for data to leave: forward, send, share, exfiltrate.
        #"\b(?:send|forward|email|share|upload|post|envia|reenvia|comparte|manda|sube)\s+(?:\w+\s+){0,6}(?:to|a|al|hacia)\s+[\w.+-]+@[\w-]+\.[\w.]+"#,
        #"\b(?:send|forward|share|envia|reenvia|comparte|manda)\s+(?:\w+\s+){0,4}(?:contacts|contactos|calendar|calendario|passwords?|contrasenas?|codes?|codigos?)\b"#,
        // Telling the assistant to act without the person.
        #"\b(?:without|sin)\s+(?:asking|confirm\w*|preguntar|confirmar|avisar)\b"#,
        #"\b(?:do\s+not|don't|no)\s+(?:tell|mention|inform|le\s+digas|menciones|informes)\b"#,
    ]

    public struct Finding: Sendable, Equatable, Codable {
        public var pattern: String
        public var excerpt: String
    }

    public func scanUserText(_ text: String) -> Finding? {
        scan(Text.fold(text), patterns: Self.direct)
    }

    /// Data fields are checked against both lists: a planted "ignore previous instructions"
    /// is as dangerous as "assistant, you must…".
    public func scanData(_ text: String) -> Finding? {
        let folded = Text.fold(text)
        return scan(folded, patterns: Self.direct) ?? scan(folded, patterns: Self.inData)
    }

    private func scan(_ folded: String, patterns: [String]) -> Finding? {
        for pattern in patterns {
            if let hit = Text.firstMatch(pattern, in: folded) {
                return Finding(pattern: pattern, excerpt: hit)
            }
        }
        return nil
    }
}

/// Did the person ask for a change? A write must trace back to the person's own message,
/// never to something the agent read. Lexical on purpose: it costs nothing and fails closed
/// (a missed verb means the agent asks the person to say it explicitly).
public enum WriteIntent {
    static let verbs: [String] = [
        #"\b(?:crea|creame|crear|agenda|agendame|agendar|programa|programar|anade|anadir|agrega|agregar|pon|ponme|apunta|marca|marcar|completa|completar|termina|cierra|guarda|registra|mueve|reprograma|cancela|borra|elimina)\b"#,
        #"\b(?:create|add|schedule|book|set\s+up|put|mark|complete|finish|check\s+off|save|move|reschedule|cancel|delete|remove|remind\s+me)\b"#,
        #"\b(?:recuerdame|recordarme|hazme\s+un\s+recordatorio)\b"#,
    ]

    public static func isRequested(in userText: String) -> Bool {
        let folded = Text.fold(userText)
        return verbs.contains { Text.firstMatch($0, in: folded) != nil }
    }
}
