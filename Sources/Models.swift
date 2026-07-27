import SwiftUI

enum CleanupCategory: String, CaseIterable, Identifiable {
    case systemCaches = "System & App Caches"
    case devTools = "Dev Tool Caches"
    case browserCaches = "Browser Caches"
    case downloads = "Downloads"
    case trash = "Trash"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .systemCaches:  return "internaldrive"
        case .devTools:      return "hammer"
        case .browserCaches: return "safari"
        case .downloads:     return "arrow.down.circle"
        case .trash:         return "trash"
        }
    }

    var subtitle: String {
        switch self {
        case .systemCaches:  return "Regenerable app & system caches, logs, crash reports"
        case .devTools:      return "Xcode, simulators, package manager caches"
        case .browserCaches: return "Cache data only — never history, passwords, or cookies"
        case .downloads:     return "Old or large files, reviewed individually — never auto-selected"
        case .trash:         return "Empty Trash — nowhere further to trash this to"
        }
    }

    /// Fixed-order categorical color (never reassigned/cycled) — see
    /// `Support.swift`'s `Color(light:dark:)`. Slots follow the validated
    /// default order from the design system's palette reference.
    var chartColor: Color {
        switch self {
        case .systemCaches:  return Color(light: "#2a78d6", dark: "#3987e5")  // slot 1 · blue
        case .devTools:      return Color(light: "#eb6834", dark: "#d95926")  // slot 2 · orange
        case .browserCaches: return Color(light: "#1baf7a", dark: "#199e70")  // slot 3 · aqua
        case .downloads:     return Color(light: "#eda100", dark: "#c98500")  // slot 4 · yellow
        case .trash:         return Color(light: "#e87ba4", dark: "#d55181") // slot 5 · magenta
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
