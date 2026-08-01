import SwiftUI

/// ncdu-style folder browser: descend into any directory under home, see
/// immediate children sorted by size with a relative bar. Unlike every other
/// tab, entries here aren't safety-classified by a scan — they're arbitrary
/// files anywhere under home — so selection/delete is deliberately scoped to
/// *files only*. Folders can only be entered, never trashed in one click,
/// which keeps a stray tap from wiping out an entire directory.
struct DiskReportView: View {
    @State private var currentDirectory = FileManager.default.homeDirectoryForCurrentUser
    @State private var entries: [DiskReportService.Entry] = []
    @State private var isLoading = false
    @State private var selectedIDs: Set<URL> = []
    @State private var showConfirm = false
    @State private var isDeleting = false

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
                    ForEach(entries) { entry in
                        row(entry)
                        Divider()
                    }
                }
            }
            footerBar
        }
        .task(id: currentDirectory) { selectedIDs = []; await load() }
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
        .padding(.top, 8)
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                Button(crumb.name) { currentDirectory = crumb.url }
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
            Button { revealInFinder(currentDirectory) } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
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
            }
            Button {
                if entry.isDirectory { currentDirectory = entry.url }
                else { revealInFinder(entry.url) }
            } label: {
                rowLabel(entry, fraction: fraction)
            }
            .buttonStyle(.plain)
        }
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

    private func deleteSelected() {
        let items = selectedEntries
        guard !items.isEmpty else { return }
        isDeleting = true
        Task {
            let trashedIDs: Set<URL> = await Task.detached(priority: .userInitiated) {
                var trashed: Set<URL> = []
                for item in items {
                    if (try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)) != nil {
                        trashed.insert(item.id)
                    }
                }
                return trashed
            }.value
            selectedIDs.subtract(trashedIDs)
            isDeleting = false
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
