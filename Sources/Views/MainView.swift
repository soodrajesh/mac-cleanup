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
            OverviewView(isCollapsed: $isOverviewCollapsed).padding([.horizontal, .top])
            categoryTabs.padding(.horizontal)
            Divider().padding(.top, 8)
            ScrollView {
                CategorySectionView(category: selectedCategory)
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
        }
        .padding()
    }

    private var categoryTabs: some View {
        Picker("", selection: $selectedCategory) {
            ForEach(CleanupCategory.allCases) { category in
                Label(category.tabLabel, systemImage: category.symbol).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.vertical, 8)
        // Overview is the dashboard you see first; the moment you pick a
        // tab you've moved on to a specific category, so collapse it to
        // give that category's content the room instead.
        .onChange(of: selectedCategory) { _ in isOverviewCollapsed = true }
    }
}
