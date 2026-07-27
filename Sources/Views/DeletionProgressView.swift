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
                Text("\(model.deletionOutcomes.count) of \(model.deletionTotal)")
                    .font(.caption).foregroundStyle(.secondary)
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
                }
                HStack {
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
