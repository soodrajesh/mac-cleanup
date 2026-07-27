import Foundation

/// Moves items to macOS Trash — the one deletion path the generic
/// selection/footer flow is allowed to use. Never `removeItem`.
enum TrashService {
    struct DeletionOutcome {
        let item: ScanItem
        let success: Bool
        let error: String?
    }

    /// Moves each item to Trash in turn. A failure on one item (permission
    /// denied, file in use) is reported and the batch continues — it must
    /// never abort the whole run.
    static func moveToTrash(_ items: [ScanItem],
                             isCancelled: @escaping () -> Bool,
                             perItem: @escaping @Sendable (Int, DeletionOutcome) -> Void) {
        for (i, item) in items.enumerated() {
            if isCancelled() { break }
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                perItem(i, DeletionOutcome(item: item, success: true, error: nil))
            } catch {
                perItem(i, DeletionOutcome(item: item, success: false, error: error.localizedDescription))
            }
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
