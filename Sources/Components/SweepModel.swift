import SwiftUI

/// Shared state: scan results per category, selection, and the Trash-delete
/// flow. Mirrors JobModel's shape (ObservableObject, MainActor, run/cancel).
@MainActor
final class SweepModel: ObservableObject {
    @Published var results: [CleanupCategory: ScanResult] = [:]
    @Published var selectedIDs: Set<UUID> = []
    @Published var isDeleting = false
    @Published var deletionOutcomes: [TrashService.DeletionOutcome] = []
    @Published var deletionProgress: Double = 0
    @Published var deletionTotal: Int = 0
    /// Trash isn't itemized (see `itemLister`), so its size lives here as the
    /// single source of truth — read by both `TrashHeaderView` and the
    /// Overview chart, rather than each fetching it independently.
    @Published var trashBytes: Int64?
    /// True when `~/.Trash` can't be read (needs Full Disk Access) — kept
    /// distinct from `trashBytes == nil` (which also means "not loaded yet")
    /// so the UI never silently shows "0" when the real answer is "can't tell".
    @Published var trashAccessDenied = false
    /// When Deep Scan / App Cleaner last actually ran — `nil` means never
    /// (this launch or any prior one). Shown next to their results so a
    /// cached list isn't mistaken for a fresh one.
    @Published var deepScanLastRun: Date?
    @Published var appCleanerLastRun: Date?

    private var deletionTask: Task<Void, Never>?

    init() {
        if let cached = ScanCache.load(key: Self.cacheKey(for: .deepScan)) {
            results[.deepScan] = ScanResult(category: .deepScan, items: cached.items, isScanning: false)
            deepScanLastRun = cached.scannedAt
        }
        if let cached = ScanCache.load(key: Self.cacheKey(for: .appCleaner)) {
            results[.appCleaner] = ScanResult(category: .appCleaner, items: cached.items, isScanning: false)
            appCleanerLastRun = cached.scannedAt
        }
    }

    private static func cacheKey(for category: CleanupCategory) -> String {
        "scanCache.\(category.rawValue).v1"
    }

    func scanAll() {
        // Deep Scan and App Cleaner both look at actual personal
        // content/installed apps rather than disposable cache — they only
        // run when explicitly started, never automatically. Disk Report
        // isn't a scan at all — it's on-demand drill-down browsing with no
        // ScanResult, sized one directory level at a time by DiskReportView.
        for category in CleanupCategory.allCases
        where category != .deepScan && category != .appCleaner && category != .diskReport {
            scan(category)
        }
        refreshTrashSize()
    }

    func refreshTrashSize() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let bytes = try TrashService.trashSize()
                await MainActor.run { self.trashBytes = bytes; self.trashAccessDenied = false }
            } catch {
                await MainActor.run { self.trashBytes = nil; self.trashAccessDenied = true }
            }
        }
    }

    /// Copy for the Overview chart/legend: known category totals plus the
    /// separately-tracked Trash size, in fixed display order.
    func bytes(for category: CleanupCategory) -> Int64 {
        category == .trash ? (trashBytes ?? 0) : (results[category]?.totalBytes ?? 0)
    }

    func scan(_ category: CleanupCategory) {
        // Show "Scanning…" immediately — listing itself can shell out (brew,
        // docker, xcrun) and take real time, so it must never run on the
        // main actor.
        results[category] = ScanResult(category: category, items: [], isScanning: true)
        let lister = itemLister(for: category)

        Task.detached(priority: .userInitiated) { [weak self] in
            let items = lister()
            guard let self else { return }
            await MainActor.run { self.results[category] = ScanResult(category: category, items: items, isScanning: true) }

            let sizableURLs = items.filter { if case .cliNative = $0.removal { return false }; return true }.map(\.url)
            await SizeCalculator.sizeAll(sizableURLs) { url, size in
                Task { @MainActor [weak self] in
                    guard let self, var result = self.results[category] else { return }
                    guard let idx = result.items.firstIndex(where: { $0.url == url }) else { return }
                    result.items[idx].status = size.map { .sized($0) } ?? .failed("Could not measure size")
                    self.results[category] = result
                }
            }
            await MainActor.run {
                guard var result = self.results[category] else { return }
                result.isScanning = false
                self.results[category] = result
                if category == .deepScan || category == .appCleaner {
                    let now = Date()
                    if category == .deepScan { self.deepScanLastRun = now } else { self.appCleanerLastRun = now }
                    ScanCache.save(key: Self.cacheKey(for: category), scannedAt: now, items: result.items)
                }
            }
        }
    }

    private func itemLister(for category: CleanupCategory) -> () -> [ScanItem] {
        switch category {
        case .systemCaches:  return CacheScanService.listItems
        case .devTools:      return { DevToolScanService.listItems() + BrewService.listItems() + DockerService.listItems() }
        case .browserCaches: return BrowserScanService.listItems
        case .downloads:     return DownloadsScanService.listItems
        case .trash:         return { [] }  // aggregate stat only — rendered by TrashHeaderView, not itemized
        case .deepScan:      return DeepScanService.listItems
        case .appCleaner:    return AppCleanerService.listItems
        case .diskReport:    return { [] }  // never scanned — see scanAll()
        }
    }

    // MARK: - Selection

    func toggle(_ item: ScanItem) {
        if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
        else { selectedIDs.insert(item.id) }
    }

    func selectAllSafe(in category: CleanupCategory) {
        guard let result = results[category] else { return }
        for item in result.items where item.safety == .safe && item.removal == .trash {
            selectedIDs.insert(item.id)
        }
    }

    var allTrashItems: [ScanItem] {
        results.values.flatMap(\.items).filter { if case .trash = $0.removal { return true }; return false }
    }

    var selectedItems: [ScanItem] {
        allTrashItems.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + ($1.status.sizeIfKnown ?? 0) }
    }

    /// Selection is a single flat set of IDs, not scoped per tab — you can
    /// check items in one category, switch tabs, and check more, then trash
    /// everything in one batch. Surfaced in the footer so that's discoverable
    /// rather than a hidden capability.
    var selectedCategories: [CleanupCategory] {
        CleanupCategory.allCases.filter { category in
            results[category]?.items.contains { selectedIDs.contains($0.id) } ?? false
        }
    }

    /// Homebrew items the user has checked — a separate action ("Run brew
    /// cleanup") from the generic Trash flow, since brew manages its own
    /// removal rather than going through Finder's Trash.
    var selectedBrewItems: [ScanItem] {
        (results[.devTools]?.items ?? []).filter {
            selectedIDs.contains($0.id) && $0.removal == .cliNative(toolName: "brew")
        }
    }

    // MARK: - CLI-native actions (simctl / docker / brew — not Trash)

    /// `simctl delete unavailable` removes every unavailable device in one
    /// call, so this is a single bulk action rather than a per-item one.
    func deleteUnavailableSimulators() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            try? DevToolScanService.deleteUnavailableSimulators()
            await MainActor.run { self.scan(.devTools) }
        }
    }

    func pruneDocker(_ item: ScanItem) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            try? DockerService.prune(label: item.displayName)
            await MainActor.run { self.scan(.devTools) }
        }
    }

    func runBrewCleanup() {
        let items = selectedBrewItems
        guard !items.isEmpty else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            try? BrewService.cleanup(formulaNames: items.map(\.displayName))
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.selectedIDs.subtract(items.map(\.id))
                self.scan(.devTools)
            }
        }
    }

    // MARK: - Deletion

    func deleteSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        isDeleting = true
        deletionOutcomes = []
        deletionProgress = 0
        deletionTotal = items.count
        let total = Double(items.count)
        deletionTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            TrashService.moveToTrash(items, isCancelled: { false }) { index, outcome in
                Task { @MainActor in
                    self.deletionOutcomes.append(outcome)
                    self.deletionProgress = Double(index + 1) / total
                }
            }
            await MainActor.run {
                self.isDeleting = false
                let removedIDs = Set(self.deletionOutcomes.filter(\.success).map { $0.item.id })
                self.selectedIDs.subtract(removedIDs)
                // Rescan affected categories so nothing stale lingers.
                let affected = Set(items.map { self.category(for: $0) })
                for category in affected { self.scan(category) }
                // Trash grew by whatever just got moved into it.
                self.refreshTrashSize()
            }
        }
    }

    /// Empties Trash via `TrashService.emptyTrash()` (the app's one sanctioned
    /// use of `removeItem`) and refreshes the tracked size afterward.
    func emptyTrash() async throws {
        try await Task.detached(priority: .userInitiated) {
            try TrashService.emptyTrash()
        }.value
        refreshTrashSize()
    }

    private func category(for item: ScanItem) -> CleanupCategory {
        for (category, result) in results where result.items.contains(where: { $0.id == item.id }) {
            return category
        }
        return .systemCaches
    }
}
