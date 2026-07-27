import Foundation

enum CleanupCategory: String, CaseIterable, Identifiable {
    case systemCaches = "System & App Caches"
    case devTools = "Dev Tool Caches"
    case browserCaches = "Browser Caches"
    case trashDownloads = "Trash & Downloads"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .systemCaches:   return "internaldrive"
        case .devTools:       return "hammer"
        case .browserCaches:  return "safari"
        case .trashDownloads: return "trash"
        }
    }

    var subtitle: String {
        switch self {
        case .systemCaches:   return "Regenerable app & system caches, logs, crash reports"
        case .devTools:       return "Xcode, simulators, package manager caches"
        case .browserCaches:  return "Cache data only — never history, passwords, or cookies"
        case .trashDownloads: return "Empty Trash, review old or large downloads"
        }
    }
}

/// .safe = fully regenerable, no functional loss beyond re-download/rebuild time.
/// .caution = not regenerable (e.g. Xcode Archives) or is user content, not cache
/// (e.g. a Downloads file) — never included in "Select All Safe".
enum SafetyLevel {
    case safe
    case caution
}

/// How an item is actually removed. `.trash` items go through Finder's Trash
/// (recoverable) via the generic selection/footer flow. `.cliNative` items have
/// no Finder-visible file to trash (or the tool manages its own version history,
/// as with Homebrew) — they're actioned individually, badged as not recoverable
/// via Trash, with their own confirmation.
enum RemovalMethod: Equatable {
    case trash
    case cliNative(toolName: String)
}

struct ScanItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let displayName: String
    let subtitle: String?
    var status: Status
    let isDirectory: Bool
    let lastAccessed: Date?
    let safety: SafetyLevel
    let removal: RemovalMethod

    enum Status: Equatable, Hashable {
        case measuring
        case sized(Int64)
        case failed(String)

        var sizeIfKnown: Int64? {
            if case .sized(let n) = self { return n }
            return nil
        }
    }

    static func == (lhs: ScanItem, rhs: ScanItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ScanResult {
    var category: CleanupCategory
    var items: [ScanItem] = []
    var isScanning = true
    var scanError: String?

    var totalBytes: Int64 {
        items.reduce(0) { $0 + ($1.status.sizeIfKnown ?? 0) }
    }
}
