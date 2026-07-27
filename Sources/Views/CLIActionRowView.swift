import SwiftUI

/// A row for a CLI-native item (Docker) — badged as not recoverable via
/// Trash, with its own confirmation before running its specific prune
/// command. No checkbox: these never join the generic Trash selection.
struct CLIActionRowView: View {
    let item: ScanItem
    let onConfirm: () -> Void

    @State private var showConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                    Text("NOT VIA TRASH")
                        .font(.caption2).bold()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if case .sized(let bytes) = item.status {
                Text(bytes.humanBytes).monospacedDigit().foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small).frame(width: 60)
            }

            Button("Remove…") { showConfirm = true }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Remove \(item.displayName) via docker?",
            isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { onConfirm() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This does not go through the macOS Trash — it cannot be undone by restoring from Trash.")
        }
    }
}
