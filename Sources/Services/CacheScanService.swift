import AppKit

/// Category 1: `~/Library/Caches/*`, `~/Library/Logs/*`, and crash reports.
/// Every item here is regenerable — always `.safe`.
enum CacheScanService {
    static func scanRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Logs"),
        ]
    }

    /// Immediate children of each root, one item per app/tool — cheap and
    /// non-recursive; `du` (via SizeCalculator) handles the actual size.
    static func listItems() -> [ScanItem] {
        var items: [ScanItem] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        for root in scanRoots() {
            guard let children = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let modified = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                items.append(ScanItem(
                    url: child,
                    displayName: friendlyName(for: child),
                    subtitle: root.lastPathComponent,
                    status: .measuring,
                    isDirectory: isDir,
                    lastAccessed: modified,
                    safety: .safe,
                    removal: .trash))
            }
        }

        // Crash reports, grouped as one item.
        let crashDirs = [
            home.appendingPathComponent("Library/Logs/DiagnosticReports"),
            home.appendingPathComponent("Library/Application Support/CrashReporter"),
        ].filter { fm.fileExists(atPath: $0.path) }
        for dir in crashDirs {
            items.append(ScanItem(
                url: dir,
                displayName: "Crash Reports (\(dir.deletingLastPathComponent().lastPathComponent))",
                subtitle: "Diagnostic reports",
                status: .measuring,
                isDirectory: true,
                lastAccessed: nil,
                safety: .safe,
                removal: .trash))
        }

        return items
    }

    /// Resolves a Caches/Logs bundle-ID folder name (e.g. "com.apple.Safari")
    /// to the owning app's display name when possible.
    private static func friendlyName(for url: URL) -> String {
        let raw = url.lastPathComponent
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw),
           let bundle = Bundle(url: app),
           let name = bundle.infoDictionary?["CFBundleName"] as? String {
            return name
        }
        return raw
    }
}
