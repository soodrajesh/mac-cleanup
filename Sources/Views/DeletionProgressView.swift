import SwiftUI

/// Live progress while items move to Trash, then a results summary —
/// stays open until the user dismisses it, so the summary is never missed.
struct DeletionProgressView: View {
    @EnvironmentObject var model: SweepModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isDeleting {
                Text("Moving to Trash…").font(.headline)
                ProgressView(value: model.deletionProgress)
                HStack {
                    Text("\(model.deletionOutcomes.count) of \(model.deletionTotal)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { model.cancelDeletion() }
                        .buttonStyle(.bordered)
                }
            } else {
                let succeeded = model.deletionOutcomes.filter(\.success)
                let failed = model.deletionOutcomes.filter { !$0.success }
                let freed = succeeded.reduce(Int64(0)) { $0 + ($1.item.status.sizeIfKnown ?? 0) }

                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(.green)
                Text("\(succeeded.count) moved to Trash, freed \(freed.humanBytes)")
                if !failed.isEmpty {
                    Text("\(failed.count) skipped:").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(failed.enumerated()), id: \.offset) { _, outcome in
                        Text("• \(outcome.item.displayName): \(outcome.error ?? "unknown error")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    // Most skips are Full Disk Access, not something wrong
                    // with the specific file — offer the one-click fix
                    // instead of making the user diagnose it from raw text.
                    if failed.contains(where: { ($0.error ?? "").looksLikePermissionError }) {
                        Button("Open Full Disk Access Settings…") { openFullDiskAccessSettings() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                HStack {
                    if !succeeded.isEmpty {
                        Button("Undo") {
                            model.undoLastDeletion()
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                        .help("Move everything just trashed back to where it came from")
                    }
                    Spacer()
                    Button("Done") { isPresented = false }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(width: 420)
    }
}
