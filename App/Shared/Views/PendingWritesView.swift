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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hourglass")
                Text("Waiting for you").font(.caption.weight(.semibold))
                Spacer()
                Text(write.client.label).font(.caption).foregroundStyle(.secondary)
            }
            Text(write.summary).font(.body.weight(.medium))
            if write.proposedAfterFlaggedData {
                Label(
                    "Proposed right after reading data that contained instructions for the assistant. Check it's what you asked for.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            HStack {
                Button("Confirm") { Task { await model.confirm(write) } }
                    .buttonStyle(.borderedProminent)
                Button("Discard", role: .destructive) { Task { await model.reject(write) } }
                    .buttonStyle(.bordered)
                Spacer()
                Text(write.expiresAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.4)))
    }
}
