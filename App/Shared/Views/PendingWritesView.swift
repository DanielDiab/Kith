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
        case "calendar_create_event": return ("New event", "calendar.badge.plus", "Add to Calendar", .kithMoss)
        case "reminders_complete": return ("Complete reminder", "checklist.checked", "Mark as Done", .kithMoss)
        default: return ("Change", "square.and.pencil", "Confirm", .kithMoss)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: action.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.kithAmber.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Waiting for your OK").foregroundStyle(Color.kithAmber).fontWeight(.semibold)
                        Text("· \(action.kind) · proposed by \(write.client.label)")
                        Spacer(minLength: 8)
                        Text("Expires in \(write.expiresAt, style: .relative)")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(Color.kithMuted)
                    Text(parts.headline)
                        .font(.headline)
                        .foregroundStyle(Color.kithInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let details = parts.details {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(Color.kithMuted)
                    }
                }

                if write.proposedAfterFlaggedData {
                    Label(
                        "Proposed right after reading text that tried to instruct the assistant. Make sure it's what you asked for.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.kithCoral)
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button {
                        run { await model.confirm(write) }
                    } label: {
                        Label(action.confirm, systemImage: "checkmark")
                    }
                    .buttonStyle(KithProminentButtonStyle(tint: action.tint))
                    Button("Discard", role: .destructive) {
                        run { await model.reject(write) }
                    }
                    .buttonStyle(KithQuietButtonStyle())
                    if working { ProgressView().controlSize(.small) }
                }
                .controlSize(.regular)
                .disabled(working)
            }
        }
        .padding(14)
        .background(Color.kithSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(write.proposedAfterFlaggedData ? Color.kithCoral.opacity(0.6) : Color.kithAmber.opacity(0.45), lineWidth: 1.5)
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
