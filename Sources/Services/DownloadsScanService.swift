import Foundation

/// Category: Downloads triage — old and/or large files surfaced for review,
/// never auto-deleted. Its own category, separate from Trash.
enum DownloadsScanService {
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
}
