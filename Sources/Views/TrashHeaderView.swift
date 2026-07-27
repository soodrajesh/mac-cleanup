import SwiftUI

/// Trash's aggregate size + its own Empty Trash flow. This is the one place
/// in the app that uses `removeItem` instead of `trashItem` (there's nowhere
/// further to trash Trash's own contents to), so it gets distinctly-worded,
/// unmistakable "cannot be undone" copy — separate from the generic
/// checkbox-review confirm sheet used everywhere else.
struct TrashHeaderView: View {
    @State private var trashBytes: Int64?
    @State private var isEmptying = false
    @State private var showConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        HStack {
            Image(systemName: "trash.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Trash")
                if let trashBytes {
                    Text("\(trashBytes.humanBytes) currently in Trash").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Calculating…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isEmptying {
                ProgressView().controlSize(.small)
            } else {
                Button("Empty Trash…") { showConfirm = true }
                    .buttonStyle(.bordered)
                    .disabled((trashBytes ?? 0) == 0)
            }
        }
        .padding(.vertical, 6)
        .task { refresh() }
        .confirmationDialog(
            "Permanently empty the Trash?",
            isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) { performEmpty() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone — items in Trash will be permanently deleted, not moved anywhere recoverable.")
        }
        .alert("Couldn't Empty Trash", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    private func refresh() {
        Task.detached(priority: .utility) {
            let bytes = TrashDownloadsService.trashSize()
            await MainActor.run { trashBytes = bytes }
        }
    }

    private func performEmpty() {
        isEmptying = true
        Task.detached(priority: .userInitiated) {
            do {
                try TrashDownloadsService.emptyTrash()
                await MainActor.run { isEmptying = false; refresh() }
            } catch {
                await MainActor.run { isEmptying = false; errorMessage = error.localizedDescription }
            }
        }
    }
}
