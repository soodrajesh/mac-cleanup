import SwiftUI

struct MainView: View {
    @EnvironmentObject var model: SweepModel
    @State private var showConfirmSheet = false
    @State private var showProgressSheet = false
    @State private var diskStats: DiskInfoService.VolumeStats?
    @State private var selectedCategory: CleanupCategory = .systemCaches
    @State private var isOverviewCollapsed = false
    /// Session-only dismissal — `model.trashAccessDenied` is the live signal
    /// (re-checked on every Rescan), so this doesn't need to persist across
    /// launches: if access is still missing next time, the banner is exactly
    /// as relevant as it was this time, and permanently silencing it would
    /// let a real, fixable problem go unnoticed indefinitely.
    @State private var dismissedAccessBanner = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.trashAccessDenied && !dismissedAccessBanner {
                fullDiskAccessBanner
                Divider()
            }
            // Tabs stay visible always — they're the primary navigation, not
            // something that should disappear. Overview's own collapse just
            // controls how much of *its* content shows above them; whatever
            // doesn't fit on screen scrolls, so nothing is ever capped or cut
            // off to force a fit.
            ScrollView {
                VStack(spacing: 12) {
                    OverviewView(isCollapsed: $isOverviewCollapsed, diskStats: diskStats)
                    categoryTabs
                    CategorySectionView(category: selectedCategory)
                        .id(selectedCategory)
                }
                .padding()
            }
            // Disk Report has its own dedicated selection/trash footer inside
            // DiskReportView — showing this one too would double up.
            if selectedCategory != .diskReport {
                Divider()
                SelectionFooterBar(showConfirm: $showConfirmSheet)
            }
        }
        .task { diskStats = DiskInfoService.stats() }
        .sheet(isPresented: $showConfirmSheet) {
            ConfirmDeletionSheet(diskStats: diskStats) {
                showConfirmSheet = false
                showProgressSheet = true
                model.deleteSelected()
            }
        }
        .sheet(isPresented: $showProgressSheet, onDismiss: { diskStats = DiskInfoService.stats() }) {
            DeletionProgressView(isPresented: $showProgressSheet)
        }
    }

    /// Proactive rather than reactive: `trashAccessDenied` reflects reality
    /// right after the launch-time `scanAll()`, before the user has to stumble
    /// into an under-reported scan or a batch of "you don't have permission"
    /// delete failures to learn something's wrong.
    private var fullDiskAccessBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("DiskSweeper needs Full Disk Access for accurate results and to move some files to Trash.")
                .font(.caption)
            Spacer()
            Button("Grant…") { openFullDiskAccessSettings() }
                .buttonStyle(.link)
                .font(.caption)
            Button {
                dismissedAccessBanner = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }

    private var header: some View {
        HStack {
            Image(systemName: "internaldrive.fill").font(.title2)
            Text("DiskSweeper").font(.title2).bold()
            Spacer()
            if let diskStats {
                Text("\(diskStats.freeBytes.humanBytes) free of \(diskStats.totalBytes.humanBytes)")
                    .foregroundStyle(.secondary)
            }
            Button {
                model.scanAll()
                diskStats = DiskInfoService.stats()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Rescan all categories (⌘R)")
        }
        .padding()
        .background(tabShortcuts)
    }

    /// Cmd+1…6 jump straight to a tab — a segmented `Picker` has no built-in
    /// per-segment shortcut, so these are invisible buttons wired to the same
    /// selection state, sized to zero so they take no space or focus ring.
    private var tabShortcuts: some View {
        ForEach(Array(CleanupCategory.allCases.enumerated()), id: \.element) { index, category in
            if index < 9 {
                Button("") { selectedCategory = category }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            }
        }
    }

    private var categoryTabs: some View {
        Picker("", selection: $selectedCategory) {
            ForEach(CleanupCategory.allCases) { category in
                Label(category.tabLabel, systemImage: category.symbol).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // Picking a tab means you're done with the dashboard for now —
        // collapse Overview so its content doesn't sit between the tabs and
        // the category you just asked to see.
        .onChange(of: selectedCategory) { isOverviewCollapsed = true }
    }
}
