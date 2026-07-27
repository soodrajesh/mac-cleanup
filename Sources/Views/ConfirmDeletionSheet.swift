import SwiftUI

/// Final review before anything moves — every selected item, individually,
/// with its size. Nothing is trashed without this explicit confirmation.
struct ConfirmDeletionSheet: View {
    @EnvironmentObject var model: SweepModel
    @Environment(\.dismiss) private var dismiss
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

            HStack {
                Text("Total: \(model.selectedBytes.humanBytes)").bold()
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
