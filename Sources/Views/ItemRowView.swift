import SwiftUI

/// A checkbox row for a `.trash`-removal item — the generic reviewed-before-
/// delete path. `.caution` items get a distinct tint so they don't blend in
/// with regenerable cache folders.
struct ItemRowView: View {
    @EnvironmentObject var model: SweepModel
    let item: ScanItem

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.toggle(item)
            } label: {
                Image(systemName: model.selectedIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(model.selectedIDs.contains(item.id) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                    if item.safety == .caution {
                        Text("REVIEW")
                            .font(.caption2).bold()
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Text(item.url.abbreviatedPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            sizeLabel

            Button {
                revealInFinder(item.url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal in Finder")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var sizeLabel: some View {
        switch item.status {
        case .measuring:
            ProgressView().controlSize(.small).frame(width: 60)
        case .sized(let bytes):
            Text(bytes.humanBytes).monospacedDigit().foregroundStyle(.secondary)
        case .failed:
            Text("—").foregroundStyle(.secondary)
                .help("Could not measure size")
        }
    }
}
