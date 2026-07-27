import SwiftUI

/// Sticky footer for the generic Trash flow — the only place the app moves
/// selected items to Trash from. Nothing deletes without going through this
/// button and the confirm sheet it opens.
struct SelectionFooterBar: View {
    @EnvironmentObject var model: SweepModel
    @Binding var showConfirm: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                let count = model.selectedItems.count
                if count > 0 {
                    Text("\(count) item\(count == 1 ? "" : "s") selected · \(model.selectedBytes.humanBytes)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Select items to move to Trash").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Move Selected to Trash") { showConfirm = true }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.delete, modifiers: .command)
                    .help("Move selected items to Trash (⌘⌫)")
                    .disabled(count == 0)
            }
            let categories = model.selectedCategories
            if categories.count > 1 {
                Text("Across \(categories.count) tabs: \(categories.map(\.tabLabel).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
