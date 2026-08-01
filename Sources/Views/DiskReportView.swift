import SwiftUI

/// ncdu-style folder browser: descend into any directory under home, see
/// immediate children sorted by size with a relative bar. Unlike every other
/// tab, entries here aren't safety-classified by a scan — they're arbitrary
/// files anywhere under home — so selection/delete is deliberately scoped to
/// *files only*. Folders can only be entered, never trashed in one click,
/// which keeps a stray tap from wiping out an entire directory.
struct DiskReportView: View {
    @EnvironmentObject var model: SweepModel
    @State private var currentDirectory = FileManager.default.homeDirectoryForCurrentUser
    @State private var entries: [DiskReportService.Entry] = []
    @State private var isLoading = false
    @State private var selectedIDs: Set<URL> = []
    @State private var showConfirm = false
    @State private var isDeleting = false
    @State private var failedDeletions: [TrashService.DeletionOutcome] = []
    @State private var lastDeletionOutcomes: [TrashService.DeletionOutcome] = []
    @State private var searchText = ""
    /// Finder-style back/forward — separate from the breadcrumb (which only
    /// ever jumps to an *ancestor*) since drilling into several sibling
    /// folders in a row has no ancestor path back to the previous one.
    @State private var backStack: [URL] = []
    @State private var forwardStack: [URL] = []

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Breadcrumb from `~` down to the current directory — browsing never
    /// goes above home (that's the tab's default root), so this can just
    /// split the relative path rather than handle an arbitrary ancestor chain.
    private var breadcrumbs: [(name: String, url: URL)] {
        var result: [(String, URL)] = [("~", home)]
        guard currentDirectory != home else { return result }
        let relative = currentDirectory.path.dropFirst(home.path.count)
        var url = home
        for part in relative.split(separator: "/") {
            url = url.appendingPathComponent(String(part))
            result.append((String(part), url))
        }
        return result
    }

    private var selectedEntries: [DiskReportService.Entry] {
        entries.filter { selectedIDs.contains($0.id) }
    }
    private var selectedBytes: Int64 { selectedEntries.reduce(0) { $0 + $1.sizeBytes } }

    /// Name-only filter (unlike the category tabs' search, there's no
    /// subtitle/path worth matching separately — the row *is* the path,
    /// one directory level at a time). Supports the same `*`/`?` wildcards.
    private var filteredEntries: [DiskReportService.Entry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter { $0.url.lastPathComponent.matchesFilter(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                breadcrumbBar
                if isLoading && entries.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Scanning…").foregroundStyle(.secondary) }
                        .padding(.vertical, 8)
                } else if entries.isEmpty {
                    Text("Nothing found").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    if entries.count > 6 { searchField }
                    if filteredEntries.isEmpty && !searchText.isEmpty {
                        Text("No items match \u{201c}\(searchText)\u{201d}").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(filteredEntries) { entry in
                        row(entry)
                        Divider()
                    }
                }
            }
            footerBar
        }
        .task(id: currentDirectory) {
            selectedIDs = []; failedDeletions = []; lastDeletionOutcomes = []; searchText = ""
            await load()
        }
        .onChange(of: model.diskReportRefreshTrigger) { Task { await load() } }
        .confirmationDialog(
            "Move \(selectedEntries.count) file\(selectedEntries.count == 1 ? "" : "s") to Trash?",
            isPresented: $showConfirm, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves the selected files to Trash. \(selectedBytes.humanBytes) will be freed once Trash is emptied.")
        }
    }

    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if isDeleting {
                    ProgressView().controlSize(.small)
                    Text("Moving to Trash…").foregroundStyle(.secondary)
                } else if selectedIDs.isEmpty {
                    Text("Select files to move to Trash").foregroundStyle(.secondary)
                } else {
                    Text("\(selectedIDs.count) file\(selectedIDs.count == 1 ? "" : "s") selected · \(selectedBytes.humanBytes)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Move Selected to Trash") { showConfirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIDs.isEmpty || isDeleting)
            }
            // Failures stay visible until the next delete attempt or
            // directory change — a silently-still-checked file with no
            // explanation is exactly what made the old FileManager-direct
            // version of this confusing.
            if !failedDeletions.isEmpty {
                Text("\(failedDeletions.count) couldn't be moved to Trash:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(failedDeletions.enumerated()), id: \.offset) { _, outcome in
                    Text("• \(outcome.item.displayName): \(outcome.error ?? "unknown error")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if failedDeletions.contains(where: { ($0.error ?? "").looksLikePermissionError }) {
                    Button("Open Full Disk Access Settings…") { openFullDiskAccessSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            // Consumed by the next delete or by navigating away (see
            // `.task(id:)`), matching the generic Trash flow's one-shot Undo.
            if !lastDeletionOutcomes.isEmpty {
                HStack {
                    Text("\(lastDeletionOutcomes.count) file\(lastDeletionOutcomes.count == 1 ? "" : "s") moved to Trash")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Undo") { undoLastDeletion() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter by name (supports * wildcard)", text: $searchText)
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
        .padding(.bottom, 2)
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Button { goBack() } label: {
                Image(systemName: "chevron.backward")
            }
            .buttonStyle(.borderless)
            .disabled(backStack.isEmpty)
            .help("Back")
            .accessibilityLabel("Back")
            Button { goForward() } label: {
                Image(systemName: "chevron.forward")
            }
            .buttonStyle(.borderless)
            .disabled(forwardStack.isEmpty)
            .help("Forward")
            .accessibilityLabel("Forward")
            ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                Button(crumb.name) { navigate(to: crumb.url) }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == breadcrumbs.count - 1 ? Color.primary : Color.accentColor)
                    .font(.subheadline)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
                if index < breadcrumbs.count - 1 {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            }
            // The app's global Rescan button skips Disk Report entirely (it's
            // on-demand browsing, not a tracked ScanResult) — this is the
            // only way to refresh sizes here after files change underneath.
            Button { Task { await load() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh this folder's sizes")
            .accessibilityLabel("Refresh this folder's sizes")
            Button { revealInFinder(currentDirectory) } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal in Finder")
        }
    }

    private func row(_ entry: DiskReportService.Entry) -> some View {
        let maxSize = entries.first?.sizeBytes ?? 1
        let fraction = maxSize > 0 ? Double(entry.sizeBytes) / Double(maxSize) : 0
        let isSelected = selectedIDs.contains(entry.id)
        return HStack(spacing: 10) {
            // Only files are selectable — entering a folder is one tap away,
            // but trashing one outright isn't offered from this view.
            if entry.isDirectory {
                Color.clear.frame(width: 16)
            } else {
                Button {
                    if isSelected { selectedIDs.remove(entry.id) } else { selectedIDs.insert(entry.id) }
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.url.lastPathComponent)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(.isButton)
            }
            Button {
                if entry.isDirectory { navigate(to: entry.url) }
                else { revealInFinder(entry.url) }
            } label: {
                rowLabel(entry, fraction: fraction)
            }
            .buttonStyle(.plain)
        }
    }

    /// Drilling into a folder or jumping via the breadcrumb both push the
    /// departed directory onto the back stack and clear forward — the
    /// standard Finder-style history contract (a fresh move invalidates
    /// wherever "forward" used to point).
    private func navigate(to url: URL) {
        guard url != currentDirectory else { return }
        backStack.append(currentDirectory)
        forwardStack.removeAll()
        currentDirectory = url
    }

    private func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentDirectory)
        currentDirectory = previous
    }

    private func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentDirectory)
        currentDirectory = next
    }

    private func rowLabel(_ entry: DiskReportService.Entry, fraction: Double) -> some View {
        HStack(spacing: 10) {
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                    .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                Text(entry.url.lastPathComponent)
                    .lineLimit(1)
                Spacer()
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: geo.size.width * fraction, alignment: .leading)
                }
                .frame(width: 80, height: 8)
                Text(entry.sizeBytes.humanBytes)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                if entry.isDirectory {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
        }
        .contentShape(Rectangle())
    }

    /// Wraps a Report entry as a `ScanItem` so deletion can go through the
    /// same `TrashService` every other tab uses — one deletion path, one
    /// place that knows how to report per-item failures, instead of a
    /// second FileManager-direct implementation that silently dropped them.
    private func asScanItem(_ entry: DiskReportService.Entry) -> ScanItem {
        ScanItem(url: entry.url, displayName: entry.url.lastPathComponent, subtitle: nil,
                 status: .sized(entry.sizeBytes), isDirectory: entry.isDirectory, lastAccessed: nil,
                 safety: .caution, removal: .trash)
    }

    private func deleteSelected() {
        let items = selectedEntries.map(asScanItem)
        guard !items.isEmpty else { return }
        isDeleting = true
        failedDeletions = []
        lastDeletionOutcomes = []
        Task {
            // No per-item progress UI here (unlike the generic Trash flow's
            // DeletionProgressView), so outcomes are just collected as a
            // plain array inside the detached task — no per-item MainActor
            // hop, no ordering to reason about.
            let outcomes = await Task.detached(priority: .userInitiated) {
                // `moveToTrash`'s loop calls `perItem` synchronously on this
                // same thread — never concurrently — so `nonisolated(unsafe)`
                // just opts out of a conservative compiler warning that
                // doesn't reflect an actual race, not real unsynchronized
                // access from multiple threads.
                nonisolated(unsafe) var outcomes: [TrashService.DeletionOutcome] = []
                TrashService.moveToTrash(items, isCancelled: { false }) { _, outcome in
                    outcomes.append(outcome)
                }
                return outcomes
            }.value
            let trashedIDs = Set(outcomes.filter(\.success).map(\.item.url))
            failedDeletions = outcomes.filter { !$0.success }
            lastDeletionOutcomes = outcomes.filter(\.success)
            selectedIDs.subtract(trashedIDs)
            isDeleting = false
            await load()
        }
    }

    /// Restores this directory's most recent successful delete — one-shot,
    /// same contract as the generic Trash flow's Undo: consumed immediately
    /// so a second tap has nothing left to restore.
    private func undoLastDeletion() {
        let outcomes = lastDeletionOutcomes
        guard !outcomes.isEmpty else { return }
        lastDeletionOutcomes = []
        Task {
            await Task.detached(priority: .userInitiated) {
                TrashService.restore(outcomes)
            }.value
            await load()
        }
    }

    private func load() async {
        isLoading = true
        let dir = currentDirectory
        let result = await Task.detached(priority: .userInitiated) {
            DiskReportService.children(of: dir)
        }.value
        guard dir == currentDirectory else { return }  // stale — user navigated again before this returned
        entries = result
        isLoading = false
    }
}
