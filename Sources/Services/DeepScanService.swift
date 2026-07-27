import Foundation

/// Deep Scan — the one category that looks at actual personal content
/// (Documents, Desktop, Pictures, Movies), so unlike everything else it's
/// opt-in: `SweepModel.scanAll()` skips it, a user has to explicitly start
/// it. Flags individual large files only — no age check, since a file
/// sitting in Documents for years is often exactly the one you meant to
/// keep, unlike a stale Downloads item. Every result is `.caution`: never
/// swept up by "Select All Safe".
enum DeepScanService {
    static let sizeThresholdBytes: Int64 = 200 * 1024 * 1024  // 200 MB

    static let defaultRoots = ["Documents", "Desktop", "Pictures", "Movies"]

    static func listItems() -> [ScanItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var items: [ScanItem] = []
        for rootName in defaultRoots {
            let rootURL = home.appendingPathComponent(rootName)
            guard fm.fileExists(atPath: rootURL.path) else { continue }
            items += scan(root: rootURL, label: rootName)
        }
        return items
    }

    /// Recurses through `root`, reporting individual files at or above the
    /// size threshold. Bundles/packages (`.photoslibrary`, `.app`, etc.) are
    /// treated as one leaf item sized as a whole rather than descended into
    /// — otherwise a single Photos library would explode into thousands of
    /// misleading "large file" results for its internal storage.
    private static func scan(root: URL, label: String) -> [ScanItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }  // keep walking past a subfolder we can't read
        ) else { return [] }

        var items: [ScanItem] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey])

            if values?.isPackage == true {
                enumerator.skipDescendants()
                let size = SizeCalculator.size(of: url) ?? 0
                if size >= sizeThresholdBytes {
                    items.append(makeItem(url: url, label: label, size: size, modified: values?.contentModificationDate))
                }
                continue
            }
            if values?.isDirectory == true { continue }  // recurse in; folders themselves aren't reported

            guard let fileSize = values?.fileSize, Int64(fileSize) >= sizeThresholdBytes else { continue }
            items.append(makeItem(url: url, label: label, size: Int64(fileSize), modified: values?.contentModificationDate))
        }
        return items
    }

    private static func makeItem(url: URL, label: String, size: Int64, modified: Date?) -> ScanItem {
        ScanItem(
            url: url,
            displayName: url.lastPathComponent,
            subtitle: "\(label) · \(size.humanBytes)",
            status: .sized(size),
            isDirectory: false,
            lastAccessed: modified,
            safety: .caution,
            removal: .trash)
    }
}
