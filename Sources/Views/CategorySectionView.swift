import SwiftUI

/// One category's full content — live-updating total as sizes stream in,
/// "Select All Safe", and the item list. Shown as the active tab's detail in
/// `MainView`, so it's always fully expanded (no per-section collapse —
/// switching tabs already handles showing one category at a time). Dev Tool
/// Caches additionally splits out its three CLI-native subsections
/// (simulators, Homebrew, Docker), each with its own action separate from
/// the generic Trash flow.
struct CategorySectionView: View {
    @EnvironmentObject var model: SweepModel
    let category: CleanupCategory

    @State private var showSimctlConfirm = false
    @State private var showBrewConfirm = false
    @State private var searchText = ""

    private var result: ScanResult? { model.results[category] }

    private var allTrashItems: [ScanItem] { sortedBySize((result?.items ?? []).filter { $0.removal == .trash }) }
    /// Filters by name, subtitle, or path — a category like Deep Scan can run
    /// long, so narrowing by typed text beats scrolling the whole list.
    private var trashItems: [ScanItem] {
        guard !searchText.isEmpty else { return allTrashItems }
        return allTrashItems.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || ($0.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
                || $0.url.path.localizedCaseInsensitiveContains(searchText)
        }
    }
    private var simctlItems: [ScanItem] { sortedBySize((result?.items ?? []).filter { $0.removal == .cliNative(toolName: "simctl") }) }
    private var brewItems: [ScanItem] { sortedBySize((result?.items ?? []).filter { $0.removal == .cliNative(toolName: "brew") }) }
    private var dockerItems: [ScanItem] { sortedBySize((result?.items ?? []).filter { $0.removal == .cliNative(toolName: "docker") }) }
    /// Biggest wins first, in every list — items still `.measuring` (size
    /// unknown) sink to the bottom and float up into place as they resolve.
    private func sortedBySize(_ items: [ScanItem]) -> [ScanItem] {
        items.sorted { ($0.status.sizeIfKnown ?? 0) > ($1.status.sizeIfKnown ?? 0) }
    }
    /// Downloads and Deep Scan are 100% `.caution` by design, so "Select All
    /// Safe" would silently select nothing there — only show it where it
    /// can actually do something.
    private var hasSafeItems: Bool { allTrashItems.contains { $0.safety == .safe } }
    /// Only worth showing a filter box once there's enough to actually
    /// scroll through — a handful of rows doesn't need one.
    private var showsSearch: Bool { allTrashItems.count > 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if category == .trash {
                TrashHeaderView().padding(.leading, 4)
            } else if category == .deepScan && result == nil {
                DeepScanStartView().padding(.leading, 4)
            } else if category == .appCleaner && result == nil {
                AppCleanerStartView().padding(.leading, 4)
            } else {
                VStack(spacing: 0) {
                    if result?.isScanning == true && (result?.items.isEmpty ?? true) {
                        HStack { ProgressView().controlSize(.small); Text("Scanning…").foregroundStyle(.secondary) }
                            .padding(.vertical, 8)
                    } else if showsSearch {
                        searchField
                    }

                    if !(result?.isScanning == true && (result?.items.isEmpty ?? true)) {
                        if allTrashItems.isEmpty && simctlItems.isEmpty && brewItems.isEmpty && dockerItems.isEmpty {
                            Text("Nothing found").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                        } else if trashItems.isEmpty && !searchText.isEmpty {
                            Text("No items match \u{201c}\(searchText)\u{201d}").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                    }

                    ForEach(trashItems) { item in
                        ItemRowView(item: item)
                        Divider()
                    }

                    if !simctlItems.isEmpty { simctlSection }
                    if !brewItems.isEmpty { brewSection }
                    if !dockerItems.isEmpty { dockerSection }
                }
                .padding(.leading, 4)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.06)))
    }

    private var header: some View {
        HStack {
            Image(systemName: category.symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.rawValue).font(.headline)
                Text(category.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // The Trash category has no itemized scan — TrashHeaderView
            // fetches and shows its own real total below.
            if category != .trash, let result {
                if result.isScanning {
                    ProgressView().controlSize(.small)
                    // A category with a lot of items (App Cleaner sizing
                    // ~90 paths, some multi-gigabyte) can take real
                    // wall-clock time even though nothing's stuck — without
                    // this, a scan 40s into a 60s job looks identical to
                    // one that's frozen. Only counted items are `.trash`
                    // (matches what sizeAll actually sizes).
                    let sizableCount = result.items.filter { $0.removal == .trash }.count
                    if sizableCount > 0 {
                        let sizedCount = result.items.filter { $0.removal == .trash && $0.status != .measuring }.count
                        Text("\(sizedCount)/\(sizableCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(result.totalBytes.humanBytes).monospacedDigit().foregroundStyle(.secondary)
            }
            if hasSafeItems {
                Button("Select All Safe") { model.selectAllSafe(in: category) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .help("Select all safe items (⌘⇧A)")
            }
            if category == .deepScan && result != nil {
                if result?.isScanning == false, let lastRun = model.deepScanLastRun {
                    Text("Scanned \(lastRun.relativeDescription)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("Scan Again") { model.scan(.deepScan) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            if category == .appCleaner && result != nil {
                if result?.isScanning == false, let lastRun = model.appCleanerLastRun {
                    Text("Scanned \(lastRun.relativeDescription)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("Scan Again") { model.scan(.appCleaner) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Rescan after quitting an app you want to include")
            }
        }
        .padding(.vertical, 4)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter by name or path", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
        .padding(.bottom, 6)
    }

    private var simctlSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Unavailable Simulators").font(.subheadline).bold().padding(.top, 6)
            ForEach(simctlItems) { item in
                HStack {
                    Text(item.displayName)
                    Spacer()
                    if case .sized(let bytes) = item.status {
                        Text(bytes.humanBytes).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .font(.callout)
            }
            let totalBytes = simctlItems.reduce(Int64(0)) { $0 + ($1.status.sizeIfKnown ?? 0) }
            Button("Delete \(simctlItems.count) Unavailable Simulator\(simctlItems.count == 1 ? "" : "s")…") {
                showSimctlConfirm = true
            }
            .buttonStyle(.bordered)
            .confirmationDialog(
                "Delete all unavailable simulators?", isPresented: $showSimctlConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { model.deleteUnavailableSimulators() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removed via simctl, not the macOS Trash — frees \(totalBytes.humanBytes), cannot be undone.")
            }
            Divider().padding(.top, 4)
        }
    }

    private var brewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Homebrew Old Versions").font(.subheadline).bold().padding(.top, 6)
            ForEach(brewItems) { item in
                HStack(spacing: 10) {
                    Button {
                        model.toggle(item)
                    } label: {
                        Image(systemName: model.selectedIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(model.selectedIDs.contains(item.id) ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(item.displayName)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if case .sized(let bytes) = item.status {
                        Text(bytes.humanBytes).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .font(.callout)
            }
            let selected = model.selectedBrewItems
            Button(selected.isEmpty ? "Run brew cleanup" : "Run brew cleanup for \(selected.count) selected…") {
                showBrewConfirm = true
            }
            .buttonStyle(.bordered)
            .disabled(selected.isEmpty)
            .confirmationDialog(
                "Run brew cleanup for \(selected.count) formula/cask?", isPresented: $showBrewConfirm, titleVisibility: .visible) {
                Button("Run brew cleanup", role: .destructive) { model.runBrewCleanup() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removed via Homebrew, not the macOS Trash — reinstallable, but cannot be undone by restoring from Trash.")
            }
            Divider().padding(.top, 4)
        }
    }

    private var dockerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Docker").font(.subheadline).bold().padding(.top, 6)
            ForEach(dockerItems) { item in
                CLIActionRowView(item: item) { model.pruneDocker(item) }
            }
        }
    }
}
