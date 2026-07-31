import SwiftUI

/// ncdu-style read-only folder browser: descend into any directory under
/// home, see immediate children sorted by size with a relative bar. No
/// checkboxes, no Trash — Deep Scan already answers "what's safe to
/// remove"; this answers "where did the space actually go."
struct DiskReportView: View {
    @State private var currentDirectory = FileManager.default.homeDirectoryForCurrentUser
    @State private var entries: [DiskReportService.Entry] = []
    @State private var isLoading = false

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

    var body: some View {
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
        .task(id: currentDirectory) { await load() }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                Button(crumb.name) { currentDirectory = crumb.url }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == breadcrumbs.count - 1 ? Color.primary : Color.accentColor)
                    .font(.caption)
                if index < breadcrumbs.count - 1 {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
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
        return Button {
            if entry.isDirectory { currentDirectory = entry.url }
            else { revealInFinder(entry.url) }
        } label: {
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
        .buttonStyle(.plain)
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
