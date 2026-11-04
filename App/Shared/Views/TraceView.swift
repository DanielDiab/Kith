import AgentCore
import SwiftUI

/// One row per span, top to bottom, the same reading order as the trace card on the
/// portfolio (`AgentTrace.tsx`): what ran, where, how long, how many tokens, what it cost.
struct TraceView: View {
    let trace: Trace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(trace.spans) { span in
                SpanRow(span: span)
            }
            Divider()
            HStack(spacing: 12) {
                Label(trace.tier?.label ?? "No model", systemImage: trace.tier?.symbol ?? "shield")
                Text("\(trace.usage.total) tokens\(trace.usage.estimated ? " (est.)" : "")")
                Text(Format.cost(trace.costUSD))
                Text("on Claude: \(Format.cost(trace.referenceCostUSD))").foregroundStyle(.secondary)
                Spacer()
                Text(Format.ms(trace.latencyMs))
            }
            .font(.caption.monospacedDigit())
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SpanRow: View {
    let span: Span

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.callout.weight(.semibold))
                    Text(span.status.rawValue)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(color.opacity(0.15), in: Capsule())
                        .foregroundStyle(color)
                    Spacer()
                    if let usage = span.usage { Text("\(usage.total) tok").font(.caption.monospacedDigit()) }
                    Text(Format.ms(span.durationMs)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                ForEach(span.detail.keys.sorted(), id: \.self) { key in
                    Text("\(key): \(span.detail[key] ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
        }
    }

    var title: String {
        switch span.kind {
        case .inputGuard: return "Input guard"
        case .route: return "Route · \(span.tier?.label ?? span.name)"
        case .model: return "Model · \(span.model ?? span.name)"
        case .tool: return "Tool · \(span.name)"
        case .dataGuard: return "Data guard · \(span.name)"
        case .outputGuard: return "Output guard"
        case .confirmation: return "Confirmed · \(span.name)"
        }
    }

    var icon: String {
        switch span.kind {
        case .inputGuard, .outputGuard: return "checkmark.shield"
        case .dataGuard: return "exclamationmark.shield"
        case .route: return "arrow.triangle.branch"
        case .model: return span.tier?.symbol ?? "cpu"
        case .tool: return "wrench.and.screwdriver"
        case .confirmation: return "hand.thumbsup"
        }
    }

    var color: Color {
        switch span.status {
        case .ok: return .green
        case .held, .retried, .escalated: return .orange
        case .flagged: return .yellow
        case .blocked, .denied, .failed: return .red
        }
    }
}
