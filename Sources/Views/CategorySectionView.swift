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
    @State private var sortOrder: SortOrder = .size

    private enum SortOrder: String, CaseIterable, Identifiable {
        case size = "Size"
        case age = "Oldest First"
        var id: String { rawValue }
    }

    private var result: ScanResult? { model.results[category] }

    private var rawTrashItems: [ScanItem] { (result?.items ?? []).filter { $0.removal == .trash } }
    private var allTrashItems: [ScanItem] { sorted(rawTrashItems) }
    /// Filters by name, subtitle, or path — a category like Deep Scan can run
    /// long, so narrowing by typed text beats scrolling the whole list.
    /// Supports `*`/`?` glob wildcards (e.g. `*.dmg`) in addition to plain
    /// substring matches.
    private var trashItems: [ScanItem] {
        guard !searchText.isEmpty else { return allTrashItems }
        return allTrashItems.filter {
            $0.displayName.matchesFilter(searchText)
                || ($0.subtitle.map { $0.matchesFilter(searchText) } ?? false)
                || $0.url.path.matchesFilter(searchText)
        }
    }

    private var simctlItems: [ScanItem] { sorted((result?.items ?? []).filter { $0.removal == .cliNative(toolName: "simctl") }) }
    private var brewItems: [ScanItem] { sorted((result?.items ?? []).filter { $0.removal == .cliNative(toolName: "brew") }) }
    private var dockerItems: [ScanItem] { sorted((result?.items ?? []).filter { $0.removal == .cliNative(toolName: "docker") }) }
    /// Biggest-first by default; "Oldest First" only shown once at least one
    /// item actually carries a last-accessed date (Caches/Browser/Downloads
    /// track it, Dev Tools/App Cleaner/Deep Scan don't) — items with no date
    /// always sink to the bottom rather than sorting arbitrarily among them.
    private func sorted(_ items: [ScanItem]) -> [ScanItem] {
        switch sortOrder {
        case .size:
            return items.sorted { ($0.status.sizeIfKnown ?? 0) > ($1.status.sizeIfKnown ?? 0) }
        case .age:
            return items.sorted { lhs, rhs in
                switch (lhs.lastAccessed, rhs.lastAccessed) {
                case let (l?, r?): return l < r
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return false
                }
            }
        }
    }
    private var hasAgeData: Bool { rawTrashItems.contains { $0.lastAccessed != nil } }
    /// Downloads and Deep Scan are 100% `.caution` by design, so "Select All
    /// Safe" would silently select nothing there — only show it where it
    /// can actually do something.
    private var hasSafeItems: Bool { allTrashItems.contains { $0.safety == .safe } }
    /// Whether every reviewable item in this category is already checked —
    /// flips the bulk button between "Select All" and "Deselect All" so one
    /// control does both instead of needing two separate buttons.
    private var allSelected: Bool {
        !allTrashItems.isEmpty && allTrashItems.allSatisfy { model.selectedIDs.contains($0.id) }
    }
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
            } else if category == .diskReport {
                DiskReportView().padding(.leading, 4)
            } else {
                VStack(spacing: 0) {
                    if result?.isScanning == true && (result?.items.isEmpty ?? true) {
                        HStack { ProgressView().controlSize(.small); Text("Scanning…").foregroundStyle(.secondary) }
                            .padding(.vertical, 8)
                    } else if showsSearch || hasAgeData {
                        toolbarRow
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
            if !allTrashItems.isEmpty {
                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected { model.deselectAll(in: category) } else { model.selectAll(in: category) }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .keyboardShortcut("a", modifiers: .command)
                .help(allSelected ? "Deselect every item in this tab (⌘A)" : "Select every item in this tab, including ones needing review (⌘A)")
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

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            if showsSearch { searchField }
            if hasAgeData {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { order in Text(order.rawValue).tag(order) }
                }
                .labelsHidden()
                .frame(width: 130)
                .help("Sort by size or by how long since each item was last touched")
            }
        }
        .padding(.bottom, 6)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter by name or path (supports * wildcard)", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
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
                    .accessibilityLabel(item.displayName)
                    .accessibilityValue(model.selectedIDs.contains(item.id) ? "Selected" : "Not selected")
                    .accessibilityAddTraits(.isButton)
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
