import SwiftUI

/// A live-updating snapshot: a single segmented storage bar (part-to-whole
/// composition, the form this data's job calls for — not a pie/donut) plus
/// the 10 largest individually reviewable items across every category, so
/// the biggest wins are visible without expanding each section by hand.
struct OverviewView: View {
    @EnvironmentObject var model: SweepModel
    @Binding var isCollapsed: Bool
    /// For the "scanned vs. actually used" caption below — without this, a
    /// user sees e.g. "84 GB scanned" next to "245 GB" total in the header
    /// and reasonably assumes the bar accounts for the whole disk. It
    /// doesn't: these categories are deliberately just caches, Downloads,
    /// and a few content folders, not Applications or system files.
    let diskStats: DiskInfoService.VolumeStats?

    private var usedBytes: Int64? {
        guard let diskStats else { return nil }
        return diskStats.totalBytes - diskStats.freeBytes
    }

    private var entries: [(category: CleanupCategory, bytes: Int64)] {
        CleanupCategory.allCases
            .map { ($0, model.bytes(for: $0)) }
            .filter { $0.1 > 0 }
    }

    private var grandTotal: Int64 { entries.reduce(0) { $0 + $1.bytes } }

    /// Only `.trash`-removal items — CLI-native items (Homebrew/Docker/
    /// Simulator) aren't part of the generic Trash flow, so surfacing them
    /// here with a checkbox that silently does nothing would be misleading.
    /// Paired with its category so each row can carry the same color as its
    /// legend entry above — ties the two halves of Overview together instead
    /// of leaving the reader to infer it from the path text alone.
    private var topItems: [(category: CleanupCategory, item: ScanItem)] {
        model.results
            .flatMap { category, result in
                result.items
                    .filter { $0.removal == .trash && $0.status.sizeIfKnown != nil }
                    .map { (category, $0) }
            }
            .sorted { ($0.item.status.sizeIfKnown ?? 0) > ($1.item.status.sizeIfKnown ?? 0) }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        if grandTotal > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    isCollapsed.toggle()
                } label: {
                    HStack {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        Text("Overview").font(.headline)
                        Spacer()
                        Text("\(grandTotal.humanBytes) scanned").foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !isCollapsed {
                    if let usedBytes, usedBytes > grandTotal {
                        Text("Not the whole disk — \(usedBytes.humanBytes) is actually used. The rest is Applications, system files, and other locations DiskSweeper doesn't scan.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    storageBar
                    legend

                    if !topItems.isEmpty {
                        Divider().padding(.vertical, 2)
                        Text("Largest Items").font(.subheadline).bold()
                        // MainView wraps everything in one ScrollView, so
                        // this doesn't need its own height cap — the full
                        // list shows, and the page scrolls if it doesn't fit.
                        ForEach(topItems, id: \.item.id) { entry in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(entry.category.chartColor)
                                    .frame(width: 3)
                                ItemRowView(item: entry.item)
                            }
                            if entry.item.id != topItems.last?.item.id { Divider() }
                        }
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.06)))
        }
    }

    /// A single stacked bar, segments in the categories' fixed color order,
    /// each end rounded, separated by a thin surface-color gap — the storage
    /// bar pattern, not a pie: this data's job is comparing magnitudes that
    /// sum to a whole, which a bar does more precisely than arc angles.
    private var storageBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(entries, id: \.category) { entry in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(entry.category.chartColor)
                        .frame(width: segmentWidth(entry.bytes, totalWidth: proxy.size.width))
                }
            }
        }
        .frame(height: 14)
    }

    private func segmentWidth(_ bytes: Int64, totalWidth: CGFloat) -> CGFloat {
        guard grandTotal > 0, totalWidth > 0 else { return 0 }
        let gapAllowance = CGFloat(max(entries.count - 1, 0)) * 2
        let usable = max(totalWidth - gapAllowance, 0)
        return max(2, usable * CGFloat(bytes) / CGFloat(grandTotal))
    }

    /// Direct labels beside each swatch — never color alone, and never the
    /// data color on text (text stays in the secondary-ink token).
    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(entries, id: \.category) { entry in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(entry.category.chartColor).frame(width: 10, height: 10)
                    Text(entry.category.rawValue).font(.caption)
                    Spacer()
                    Text(entry.bytes.humanBytes).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }
}
