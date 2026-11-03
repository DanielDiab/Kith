import AgentEvals
import Foundation

// Usage: agent-evals [suites-dir] [--out results.json]
// Runs every suite without a model and exits non-zero if any suite is under its threshold.

var args = Array(CommandLine.arguments.dropFirst())
var outPath: String?
if let i = args.firstIndex(of: "--out"), i + 1 < args.count {
    outPath = args[i + 1]
    args.removeSubrange(i...(i + 1))
}
let dir = URL(fileURLWithPath: args.first ?? "Evals/suites")

do {
    let suites = try Suite.loadAll(in: dir)
    var results: [SuiteResult] = []
    for suite in suites { results.append(await Runner.run(suite)) }
    let report = Report(suites: results)
    print(report.markdown())
    if let outPath {
        let url = URL(fileURLWithPath: outPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.json().write(to: url)
        try report.markdown().write(to: url.deletingPathExtension().appendingPathExtension("md"), atomically: true, encoding: .utf8)
    }
    exit(report.allMeetThreshold ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("agent-evals: \(error)\n".utf8))
    exit(2)
}
