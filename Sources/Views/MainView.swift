import SwiftUI

struct MainView: View {
    @EnvironmentObject var model: SweepModel
    @State private var showConfirmSheet = false
    @State private var showProgressSheet = false
    @State private var diskStats: DiskInfoService.VolumeStats?
    @State private var selectedCategory: CleanupCategory = .systemCaches
    @State private var isOverviewCollapsed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // Tabs stay visible always — they're the primary navigation, not
            // something that should disappear. Overview's own collapse just
            // controls how much of *its* content shows above them; whatever
            // doesn't fit on screen scrolls, so nothing is ever capped or cut
            // off to force a fit.
            ScrollView {
                VStack(spacing: 12) {
                    OverviewView(isCollapsed: $isOverviewCollapsed)
                    categoryTabs
                    CategorySectionView(category: selectedCategory)
                        .id(selectedCategory)
                }
                .padding()
            }
            Divider()
            SelectionFooterBar(showConfirm: $showConfirmSheet)
        }
        .task { diskStats = DiskInfoService.stats() }
        .sheet(isPresented: $showConfirmSheet) {
            ConfirmDeletionSheet {
                showConfirmSheet = false
                showProgressSheet = true
                model.deleteSelected()
            }
        }
        .sheet(isPresented: $showProgressSheet, onDismiss: { diskStats = DiskInfoService.stats() }) {
            DeletionProgressView(isPresented: $showProgressSheet)
        }
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
        .onChange(of: selectedCategory) { _ in isOverviewCollapsed = true }
    }
}
