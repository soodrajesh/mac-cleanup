import Foundation

/// Persists an opt-in category's last scan result across launches — used by
/// both Deep Scan and App Cleaner, where a real scan (`du -a` over Documents,
/// or sizing ~90 app/leftover paths) isn't instant, so without this every
/// launch (or every tab visit) pays that cost again just to see what you
/// already saw last time. Stores only what's needed to rebuild `ScanItem`s
/// (sizes, not live file state), so a rescan is still needed to catch
/// changes on disk — this just avoids an empty tab while that catch-up
/// happens. Keyed per category so Deep Scan and App Cleaner don't collide.
enum ScanCache {
    private struct CachedItem: Codable {
        let path: String
        let displayName: String
        let subtitle: String?
        let size: Int64
        let isDirectory: Bool
    }

    private struct Cache: Codable {
        let scannedAt: Date
        let items: [CachedItem]
    }

    static func save(key: String, scannedAt: Date, items: [ScanItem]) {
        let cached = items.map {
            CachedItem(path: $0.url.path, displayName: $0.displayName, subtitle: $0.subtitle,
                       size: $0.status.sizeIfKnown ?? 0, isDirectory: $0.isDirectory)
        }
        guard let data = try? JSONEncoder().encode(Cache(scannedAt: scannedAt, items: cached)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Returns `nil` if there's no cache, or if every cached path has since
    /// vanished (stale enough that showing it would be actively misleading).
    /// Every cached item was `.caution`/`.trash` at save time (true of both
    /// Deep Scan and App Cleaner results), so that's reconstructed directly
    /// rather than round-tripped through the cache.
    static func load(key: String) -> (scannedAt: Date, items: [ScanItem])? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return nil }
        let fm = FileManager.default
        let items = cache.items
            .filter { fm.fileExists(atPath: $0.path) }
            .map {
                ScanItem(url: URL(fileURLWithPath: $0.path), displayName: $0.displayName, subtitle: $0.subtitle,
                         status: .sized($0.size), isDirectory: $0.isDirectory, lastAccessed: nil,
                         safety: .caution, removal: .trash)
            }
        guard !items.isEmpty else { return nil }
        return (cache.scannedAt, items)
    }
}
