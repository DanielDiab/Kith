import AgentCore
import AgentEvals
import AppleData
import Foundation
import ModelBackends
import Testing

/// The suites that need a real model: `Evals/model/*.json`, over the synthetic week.
///
/// Run on a Mac with Apple Intelligence on (Product ▸ Test on the KithMac scheme, or
/// `xcodebuild test -scheme KithMac`). If Ollama is running with the configured model, the
/// router can also send multi-step requests to it. Results go to `Evals/results/`, the same
/// JSON/Markdown shape as the CI suites, so the numbers can be published as they are.
@Suite("Model evals", .serialized)
struct ModelEvalTests {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func live() async -> LiveModels? {
        guard #available(macOS 26.0, *) else { return nil }
        let onDevice = OnDeviceBackend.profile()
        guard onDevice.available else { return nil }
        var backends: [any LanguageBackend] = [OnDeviceBackend()]
        var profiles = [onDevice]
        let local = ChatCompletionsBackend()
        let localProfile = await local.profile()
        profiles.append(localProfile)
        if localProfile.available { backends.append(local) }
        return LiveModels(backends: backends, profiles: profiles, privacy: .ownHardware)
    }

    @Test(arguments: ["quality", "red_team"])
    func suite(_ file: String) async throws {
        guard let live = await Self.live() else {
            print("Skipping \(file): the on-device model is not available on this Mac.")
            return
        }
        let suite = try EvalSuite.load(Self.repo.appendingPathComponent("Evals/model/\(file).json"))
        let result = await Runner.run(suite, live: live)
        let report = Report(suites: [result])
        let out = Self.repo.appendingPathComponent("Evals/results/model-\(file).json")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.json().write(to: out)
        try report.markdown().write(to: out.deletingPathExtension().appendingPathExtension("md"), atomically: true, encoding: .utf8)
        print(report.markdown())
        for c in result.cases where !c.passed {
            print("\(suite.name)/\(c.id) [\(c.tier?.rawValue ?? "-")]: \(c.failures.joined(separator: "; "))")
        }
        #expect(result.meetsThreshold, "\(result.passed)/\(result.total) under threshold \(result.threshold)")
    }
}
