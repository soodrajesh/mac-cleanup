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
            // Overview and the category tabs are mutually exclusive — the
            // dashboard and a specific category's review list both want the
            // window's room, so only one shows at a time.
            if isOverviewCollapsed {
                categoryTabs.padding(.horizontal)
                Divider().padding(.top, 8)
                ScrollView {
                    CategorySectionView(category: selectedCategory)
                        .padding()
                }
            } else {
                Spacer(minLength: 0)
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
        // Only ever shown while Overview is collapsed (see body), so there's
        // no scenario where a tab gets picked while Overview is still up —
        // no need to separately force a collapse on selection here.
        Picker("", selection: $selectedCategory) {
            ForEach(CleanupCategory.allCases) { category in
                Label(category.tabLabel, systemImage: category.symbol).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.vertical, 8)
    }
}
