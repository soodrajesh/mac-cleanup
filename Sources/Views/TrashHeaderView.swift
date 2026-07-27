import SwiftUI
import AppKit

/// The entire body of the Trash category — its aggregate size (tracked by
/// `SweepModel.trashBytes`, shared with the Overview chart) and its own
/// Empty Trash flow. This is the one place in the app that uses `removeItem`
/// instead of `trashItem` (there's nowhere further to trash Trash's own
/// contents to), so it gets distinctly-worded, unmistakable "cannot be
/// undone" copy — separate from the generic checkbox-review confirm sheet
/// used everywhere else.
struct TrashHeaderView: View {
    @EnvironmentObject var model: SweepModel
    @State private var isEmptying = false
    @State private var showConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if model.trashAccessDenied {
                    Label("Can't read Trash contents", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if let trashBytes = model.trashBytes {
                    Text("\(trashBytes.humanBytes) currently in Trash").foregroundStyle(.secondary)
                } else {
                    Text("Calculating…").foregroundStyle(.secondary)
                }
                Spacer()
                if isEmptying {
                    ProgressView().controlSize(.small)
                } else if !model.trashAccessDenied {
                    Button("Empty Trash…") { showConfirm = true }
                        .buttonStyle(.bordered)
                        .disabled((model.trashBytes ?? 0) == 0)
                }
            }
            if model.trashAccessDenied {
                HStack {
                    Text("macOS requires Full Disk Access to see what's in Trash — grant it, then relaunch DiskSweeper.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Privacy Settings…") { openFullDiskAccessSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 6)
        .task { model.refreshTrashSize() }
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

    private func performEmpty() {
        isEmptying = true
        Task {
            do {
                try await model.emptyTrash()
                isEmptying = false
            } catch {
                isEmptying = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
