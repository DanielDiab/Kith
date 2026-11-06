#if canImport(FoundationModels)
    import AgentCore
    import Foundation
    import FoundationModels

    /// Apple's on-device model through Foundation Models: the `onDevice` tier. Free, offline,
    /// a small context window (4K on the 26 SDKs; `contextSize` reports the real one).
    ///
    /// Foundation Models runs its own tool loop inside `LanguageModelSession`. Each tool given
    /// to the session is a thin wrapper whose `call` goes to the `ToolGate`, so the session
    /// never reaches EventKit directly and the same permissions, data guard and held writes
    /// apply as with any other backend.
    @available(macOS 26.0, iOS 26.0, *)
    public struct OnDeviceBackend: LanguageBackend {
        public let tier = Tier.onDevice
        public let modelName = "apple-on-device"
        public static let contextTokens = 4_096

        public init() {}

        public static func profile() -> TierProfile {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return TierProfile(tier: .onDevice, model: "apple-on-device", contextTokens: model.contextSize)
            case .unavailable(let reason):
                return TierProfile(
                    tier: .onDevice, model: "apple-on-device", contextTokens: contextTokens, available: false,
                    unavailableReason: Self.describe(reason))
            }
        }

        static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
            switch reason {
            case .deviceNotEligible: return "this device can't run Apple Intelligence"
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is turned off"
            case .modelNotReady: return "the on-device model is still downloading"
            @unknown default: return "the on-device model is unavailable"
            }
        }

        public func respond(to request: ModelRequest, tools gate: ToolGate) async throws -> ModelReply {
            let tools: [any Tool] = try request.tools.map { try GatedTool(spec: $0, gate: gate) }
            let session = LanguageModelSession(tools: tools, instructions: Instructions(request.instructions))
            let prompt = Self.render(request.messages)
            // Greedy sampling: the same question over the same data gets the same answer, so the
            // real-model evals are repeatable. The tool-calling mode is left at its default:
            // `.required` applies to every step of the session's loop, not just the first, so the
            // model never stops calling tools.
            do {
                let response = try await session.respond(to: prompt, options: GenerationOptions(samplingMode: .greedy))
                return ModelReply(text: response.content, usage: Self.usage(response, input: request.instructions + prompt))
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error { throw BackendError.contextExceeded }
                throw BackendError.failed("\(error)")
            }
        }

        /// Counted by the framework on the 27 SDKs; estimated, and marked so, before that.
        static func usage(_ response: LanguageModelSession.Response<String>, input: String) -> TokenUsage {
            #if compiler(>=6.4)  // Xcode 27: `Response.usage` is in the SDK
                if #available(macOS 27.0, iOS 27.0, *) {
                    let u = response.usage
                    return TokenUsage(
                        input: u.input.totalTokenCount, cachedInput: u.input.cachedTokenCount,
                        output: u.output.totalTokenCount, reasoning: u.output.reasoningTokenCount)
                }
            #endif
            return .estimate(input: input, output: response.content)
        }

        /// The session is created per turn, so earlier turns go in as plain text before the
        /// latest message. Corrections from the platform arrive as the last user message.
        static func render(_ messages: [ChatMessage]) -> String {
            guard messages.count > 1 else { return messages.last?.content ?? "" }
            let earlier = messages.dropLast().map { "\($0.role == .assistant ? "Assistant" : "Person"): \($0.content)" }
            return "Conversation so far:\n" + earlier.joined(separator: "\n") + "\n\nPerson: " + (messages.last?.content ?? "")
        }
    }

    /// A Foundation Models tool whose only job is to forward the call to the gate.
    @available(macOS 26.0, iOS 26.0, *)
    struct GatedTool: Tool {
        let name: String
        let description: String
        let parameters: GenerationSchema
        let gate: ToolGate

        init(spec: ToolSpec, gate: ToolGate) throws {
            self.name = spec.name
            self.description = spec.description
            self.gate = gate
            let properties = spec.parameters.map { p in
                DynamicGenerationSchema.Property(
                    name: p.name, description: p.description, schema: Self.schema(for: p.type), isOptional: !p.required)
            }
            let root = DynamicGenerationSchema(name: spec.name, description: spec.description, properties: properties)
            self.parameters = try GenerationSchema(root: root, dependencies: [])
        }

        static func schema(for type: String) -> DynamicGenerationSchema {
            switch type {
            case "boolean": return DynamicGenerationSchema(type: Bool.self)
            case "integer": return DynamicGenerationSchema(type: Int.self)
            default: return DynamicGenerationSchema(type: String.self)
            }
        }

        func call(arguments: GeneratedContent) async throws -> String {
            let parsed = (try? JSONValue.parse(arguments.jsonString)) ?? [:]
            let result = await gate.execute(ToolCall(id: UUID().uuidString, name: name, arguments: parsed))
            return result.jsonString()
        }
    }
#endif
