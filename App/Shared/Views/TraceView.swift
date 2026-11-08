import AgentCore
import SwiftUI

/// How an answer was made, as a timeline: what ran, where, how long, and what each check
/// decided, in plain words first and the raw detail underneath. Same reading order as the
/// trace card on the portfolio (`AgentTrace.tsx`).
struct TraceView: View {
    let trace: Trace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summary
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(trace.spans.enumerated()), id: \.element.id) { index, span in
                    SpanRow(span: span, isLast: index == trace.spans.count - 1)
                }
            }
        }
        .padding(16)
        .background(Color.kithSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.kithLine))
    }

    private var summary: some View {
        HStack(spacing: 0) {
            Stat(title: "Ran on", value: trace.tier?.label ?? "No model", tint: trace.tier?.tint)
            divider
            Stat(title: "Tokens", value: trace.usage.total.formatted() + (trace.usage.estimated ? "*" : ""))
            divider
            Stat(title: "Cost", value: Format.cost(trace.costUSD))
            divider
            Stat(title: "On Claude", value: Format.cost(trace.referenceCostUSD))
            divider
            Stat(title: "Time", value: Format.ms(trace.latencyMs))
        }
        .padding(.vertical, 10)
        .background(Color.kithSunken.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var divider: some View { Rectangle().fill(Color.kithLine).frame(width: 1, height: 28) }
}

private struct Stat: View {
    let title: String
    let value: String
    var tint: Color? = nil

    var body: some View {
        VStack(spacing: 3) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(Color.kithMuted)
            Text(value).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(tint ?? Color.kithInk)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SpanRow: View {
    let span: Span
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(.callout.weight(.semibold)).foregroundStyle(Color.kithInk)
                    Spacer(minLength: 8)
                    if let usage = span.usage {
                        Text("\(usage.total.formatted()) tok").font(.caption.monospacedDigit()).foregroundStyle(Color.kithMuted)
                    }
                    Text(Format.ms(span.durationMs)).font(.caption.monospacedDigit()).foregroundStyle(Color.kithMuted.opacity(0.8))
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(span.status == .ok ? Color.kithMuted : tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(technical, id: \.self) { line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.kithMuted.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.kithSunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
        // The line joining this step to the next, as tall as the row itself.
        .background(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(Color.kithLine)
                    .frame(width: 2)
                    .padding(.top, 26)
                    .padding(.bottom, 2)
                    .padding(.leading, 11)
            }
        }
    }

    // MARK: Plain words

    private var title: String {
        switch span.kind {
        case .inputGuard:
            return span.status == .blocked ? "Message blocked" : "Message checked"
        case .route:
            if span.status == .failed { return "No model available" }
            let escalated = span.status == .escalated
            switch span.tier {
            case .onDevice: return "Kept on this device"
            case .localOpen: return escalated ? "Moved up to your Mac" : "Sent to your Mac"
            case .claude: return escalated ? "Moved up to Claude" : "Sent to Claude"
            case nil: return span.name
            }
        case .model:
            return span.status == .failed ? "Model failed" : "\(Self.modelName(span.model ?? span.name)) answered"
        case .tool:
            return Self.toolTitle(span.name)
        case .dataGuard:
            return "Suspicious text withheld"
        case .outputGuard:
            if span.status == .ok { return "Answer checked" }
            return span.detail["gap"] != nil ? "Sent back to the model" : "Sent back: not in your data"
        case .confirmation:
            return "You confirmed"
        }
    }

    private var subtitle: String? {
        let d = span.detail
        switch span.kind {
        case .inputGuard:
            if span.status == .blocked { return d["match"].map { "It looked like an instruction: “\($0)”" } ?? "Too long to process." }
            return nil
        case .route:
            var parts: [String] = []
            if let reason = d["reason"] { parts.append(reason.capitalizedFirst) }
            for key in d.keys.sorted() where key.hasPrefix("skipped.") {
                let tier = Tier(rawValue: String(key.dropFirst("skipped.".count)))?.label ?? key
                parts.append("Skipped \(tier): \(d[key] ?? "")")
            }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        case .model:
            return d["error"] ?? d["note"]
        case .tool:
            switch span.status {
            case .held: return d["summary"].map { "Waiting for your OK: \($0)" } ?? "Waiting for your OK"
            case .failed: return d["error"].map { "Refused: \($0)" } ?? d["missing"].map { "Missing: \($0)" }
            case .denied: return d["reason"].map { "Not allowed: \($0)" }
            default: return nil
            }
        case .dataGuard:
            let n = Int(d["withheld_fields"] ?? "") ?? 1
            return "\(n) \(n == 1 ? "field" : "fields") in \(Self.dataName(span.name)) told the assistant what to do. No model saw \(n == 1 ? "it" : "them")."
        case .outputGuard:
            if span.status == .ok {
                let n = Int(d["claims_checked"] ?? "") ?? 0
                return n == 0 ? "No dates, times, names or figures to check." : "\(n) dates, times, names and figures match your data."
            }
            if let gap = d["gap"] { return gap.capitalizedFirst }
            if let unverified = d["unverified"] { return "Couldn't find \(unverified)" }
            return nil
        case .confirmation:
            return d["summary"]
        }
    }

    /// The raw values worth seeing as written: what a tool was called with, what was withheld.
    private var technical: [String] {
        let d = span.detail
        var out: [String] = []
        if span.kind == .tool, let args = d["args"] { out.append(args) }
        if span.kind == .dataGuard, let excerpt = d["excerpt"] { out.append(excerpt) }
        return out
    }

    private var icon: String {
        switch span.kind {
        case .inputGuard: return span.status == .blocked ? "hand.raised.fill" : "text.magnifyingglass"
        case .outputGuard: return span.status == .ok ? "checkmark" : "arrow.uturn.backward"
        case .dataGuard: return "exclamationmark"
        case .route: return span.status == .escalated ? "arrow.up.forward" : "arrow.triangle.branch"
        case .model: return span.tier.map { $0 == .onDevice ? "apple.intelligence" : $0.symbol } ?? "cpu"
        case .tool: return span.status == .held ? "hourglass" : Self.toolSymbol(span.name)
        case .confirmation: return "checkmark"
        }
    }

    private var tint: Color {
        switch span.status {
        case .ok:
            switch span.kind {
            case .inputGuard, .outputGuard, .confirmation: return .kithLeaf
            case .route: return span.tier?.tint ?? .kithMoss
            case .model: return span.tier?.tint ?? .kithMoss
            case .tool: return .kithMoss
            case .dataGuard: return .kithCoral
            }
        case .held, .retried, .escalated: return .kithAmber
        case .flagged: return .kithCoral
        case .blocked, .denied, .failed: return .kithCoral
        }
    }

    static func toolTitle(_ name: String) -> String {
        switch name {
        case "calendar_list_events": return "Read your calendar"
        case "calendar_create_event": return "Proposed an event"
        case "reminders_list": return "Read your reminders"
        case "reminders_complete": return "Proposed completing a reminder"
        case "contacts_search": return "Searched your contacts"
        default: return name
        }
    }

    static func dataName(_ tool: String) -> String {
        if tool.hasPrefix("calendar") { return "your calendar" }
        if tool.hasPrefix("reminders") { return "your reminders" }
        if tool.hasPrefix("contacts") { return "your contacts" }
        return tool
    }

    static func toolSymbol(_ name: String) -> String {
        switch name {
        case "calendar_list_events": return "calendar"
        case "calendar_create_event": return "calendar.badge.plus"
        case "reminders_list": return "checklist"
        case "reminders_complete": return "checklist.checked"
        case "contacts_search": return "person.crop.circle"
        default: return "wrench.and.screwdriver"
        }
    }

    static func modelName(_ id: String) -> String {
        switch id {
        case "apple-on-device": return "Apple's on-device model"
        default:
            // "qwen3:8b" reads as "Qwen3 8B"; anything else as the server names it.
            let parts = id.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return id }
            return String(parts[0]).capitalizedFirst + " " + parts[1].uppercased()
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
