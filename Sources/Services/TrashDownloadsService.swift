import Foundation

/// Category 4: Trash (shown as one aggregate stat with its own Empty Trash
/// action, not itemized here — it's already the safe zone) and a Downloads
/// triage list (old/large files surfaced for review, never auto-deleted).
enum TrashDownloadsService {
    static let ageThresholdDays = 90
    static let sizeThresholdBytes: Int64 = 100 * 1024 * 1024  // 100 MB

    /// Downloads items old and/or large enough to be worth reviewing.
    /// `.caution` — these are user files, not disposable cache, so they're
    /// never swept up by "Select All Safe".
    static func listItems() -> [ScanItem] {
        let fm = FileManager.default
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard let children = try? fm.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: [.isDirectoryKey, .contentAccessDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }

        return children.compactMap { url -> ScanItem? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentAccessDateKey, .contentModificationDateKey])
            let isDir = values?.isDirectory ?? false
            // APFS access-date updates are often deferred/disabled, so fall back to modification date.
            let lastUsed = values?.contentAccessDate ?? values?.contentModificationDate
            let ageDays = lastUsed?.daysAgo ?? 0
            let size = SizeCalculator.size(of: url) ?? 0

            let isOld = ageDays >= ageThresholdDays
            let isLarge = size >= sizeThresholdBytes
            guard isOld || isLarge else { return nil }

            var badges: [String] = []
            if isOld { badges.append("\(ageDays)d old") }
            if isLarge { badges.append(size.humanBytes) }

            return ScanItem(
                url: url,
                displayName: url.lastPathComponent,
                subtitle: badges.joined(separator: " · "),
                status: .sized(size),
                isDirectory: isDir,
                lastAccessed: lastUsed,
                safety: .caution,
                removal: .trash)
        }
    }

    /// Sum of everything currently in Trash.
    static func trashSize() -> Int64 {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return 0 }
        return children.reduce(0) { $0 + (SizeCalculator.size(of: $1) ?? 0) }
    }

    /// The one sanctioned use of `removeItem` in the app — there's nowhere
    /// further to trash Trash's own contents to. Callers must show
    /// unmistakably-worded "cannot be undone" copy before calling this.
    static func emptyTrash() throws {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for child in children {
            try? FileManager.default.removeItem(at: child)
        }
    }
}
