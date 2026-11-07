import AgentCore
import SwiftUI

/// Every change waits here until the person says yes. MCP clients and the agent can only
/// propose; this is the only place a write runs.
struct PendingWritesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.pending) { write in
                PendingCard(write: write)
            }
        }
    }
}

struct PendingCard: View {
    @Environment(AppModel.self) private var model
    let write: PendingWrite
    @State private var working = false

    /// The summary is written by the tool, never by the model, so it is shown exactly as is;
    /// the first part ("Create “Lunch”") becomes the headline and the rest the details.
    private var parts: (headline: String, details: String?) {
        let pieces = write.summary.components(separatedBy: " · ")
        guard pieces.count > 1 else { return (write.summary, nil) }
        return (pieces[0], pieces.dropFirst().joined(separator: " · "))
    }

    private var action: (kind: String, symbol: String, confirm: String, tint: Color) {
        switch write.tool {
        case "calendar_create_event": return ("New event", "calendar.badge.plus", "Add to Calendar", .red)
        case "reminders_complete": return ("Complete reminder", "checklist.checked", "Mark as Done", .orange)
        default: return ("Change", "square.and.pencil", "Confirm", .accentColor)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: action.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(action.tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(action.kind) · proposed by \(write.client.label)")
                        Spacer(minLength: 8)
                        Text("Expires in \(write.expiresAt, style: .relative)")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(parts.headline)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let details = parts.details {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if write.proposedAfterFlaggedData {
                    Label(
                        "Proposed right after reading text that tried to instruct the assistant. Make sure it's what you asked for.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button {
                        run { await model.confirm(write) }
                    } label: {
                        Text(action.confirm).frame(minWidth: 90)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Discard", role: .destructive) {
                        run { await model.reject(write) }
                    }
                    .buttonStyle(.bordered)
                    if working { ProgressView().controlSize(.small) }
                }
                .controlSize(.regular)
                .disabled(working)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(write.proposedAfterFlaggedData ? Color.orange.opacity(0.6) : Color.primary.opacity(0.1))
        )
    }

    private func run(_ work: @escaping () async -> Void) {
        working = true
        Task {
            await work()
            working = false
        }
    }
}
