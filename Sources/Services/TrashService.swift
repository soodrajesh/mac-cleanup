import Foundation
import Darwin

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

    /// Thrown when every existing Trash location fails to enumerate — most
    /// likely a Full Disk Access / permission issue. Distinct from "Trash is
    /// genuinely empty" so callers never silently report 0 when the real
    /// answer is "can't tell."
    struct TrashAccessDenied: LocalizedError {
        var errorDescription: String? {
            "DiskSweeper couldn't read Trash. If this persists, grant it Full Disk Access in System Settings → Privacy & Security, then relaunch DiskSweeper."
        }
    }

    /// macOS keeps more than one Trash location: `~/.Trash` for items
    /// trashed from inside your home folder, and a per-volume, per-user
    /// `/.Trashes/<uid>` for items trashed from elsewhere on that volume
    /// (including the boot volume itself) — Finder's unified Trash window
    /// aggregates all of them, so this has to as well or it silently
    /// undercounts (which is exactly what a `~/.Trash`-only check does).
    private static func trashRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        var roots = [home]
        let uid = getuid()
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        for volume in volumes {
            let volumeTrash = volume.appendingPathComponent(".Trashes").appendingPathComponent("\(uid)")
            if !roots.contains(where: { $0.standardizedFileURL.path == volumeTrash.standardizedFileURL.path }) {
                roots.append(volumeTrash)
            }
        }
        return roots
    }

    /// Aggregates every existing Trash root. Only throws if *every* root
    /// that exists failed to read — a root that simply doesn't exist yet
    /// (e.g. never trashed anything from that volume) isn't an error.
    private static func trashContents() throws -> [URL] {
        var items: [URL] = []
        var existingCount = 0
        var deniedCount = 0
        for root in trashRoots() {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            existingCount += 1
            do {
                items += try FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            } catch {
                deniedCount += 1
            }
        }
        if existingCount > 0 && deniedCount == existingCount {
            throw TrashAccessDenied()
        }
        return items
    }

    /// Sum of everything currently in Trash. Throws `TrashAccessDenied` if
    /// the folder listing fails, or if it succeeds but *every* item then
    /// fails to size — `du` on a trashed item can itself be denied even
    /// when listing the folder isn't, which would otherwise silently
    /// collapse to a false "0 bytes" via `?? 0` on every item.
    static func trashSize() throws -> Int64 {
        let contents = try trashContents()
        guard !contents.isEmpty else { return 0 }
        var total: Int64 = 0
        var failures = 0
        for url in contents {
            if let size = SizeCalculator.size(of: url) { total += size } else { failures += 1 }
        }
        if failures == contents.count { throw TrashAccessDenied() }
        return total
    }

    /// The one sanctioned use of `removeItem` in the app — there's nowhere
    /// further to trash Trash's own contents to. Callers must show
    /// unmistakably-worded "cannot be undone" copy before calling this.
    static func emptyTrash() throws {
        for child in try trashContents() {
            try? FileManager.default.removeItem(at: child)
        }
    }
}
