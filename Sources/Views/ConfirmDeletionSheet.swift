import SwiftUI

/// Final review before anything moves — every selected item, individually,
/// with its size. Nothing is trashed without this explicit confirmation.
struct ConfirmDeletionSheet: View {
    @EnvironmentObject var model: SweepModel
    @Environment(\.dismiss) private var dismiss
    /// For the "X free → Y free" projection below — moving to Trash doesn't
    /// free space until Trash is emptied, so this is framed as a preview of
    /// the eventual outcome, not an immediate result.
    let diskStats: DiskInfoService.VolumeStats?
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move \(model.selectedItems.count) Items to Trash")
                .font(.headline)
            Text("These items will move to macOS Trash — recoverable until Trash is emptied.")
                .font(.caption).foregroundStyle(.secondary)

            List(model.selectedItems) { item in
                HStack {
                    Text(item.displayName)
                    Spacer()
                    Text((item.status.sizeIfKnown ?? 0).humanBytes)
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(minHeight: 200)

            VStack(alignment: .leading, spacing: 2) {
                Text("Total: \(model.selectedBytes.humanBytes)").bold()
                if let diskStats {
                    let projectedFree = diskStats.freeBytes + model.selectedBytes
                    Text("\(diskStats.freeBytes.humanBytes) free → ~\(projectedFree.humanBytes) free once Trash is emptied")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Move to Trash") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 480, height: 380)
    }
}
