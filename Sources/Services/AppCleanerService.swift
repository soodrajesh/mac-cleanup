import AppKit
import Foundation

/// App Cleaner — lists installed apps plus their leftover files, so
/// uninstalling doesn't leave orphaned Preferences/Application
/// Support/Containers behind. Deliberately conservative, per the app's
/// safety-first mandate:
///   - **Exact bundle-ID matching only.** No fuzzy name search across
///     `~/Library` — every leftover path is a deterministic lookup keyed by
///     the app's own `CFBundleIdentifier` (or, for the couple of locations
///     that are conventionally keyed by name instead, the app's own exact
///     `CFBundleName`). Nothing is guessed.
///   - **Apple's own apps are never listed.** Any bundle ID starting with
///     "com.apple." is skipped outright — this tool has no business
///     touching them, matched or not.
///   - **Running apps are never listed.** Removing a running app's files
///     out from under it can corrupt its state; quit it first, then rescan.
///   - **User-space only.** Every path here is under `~/Library` or
///     `/Applications` — nothing in `/Library`, `/System`, or anywhere else
///     that would need `sudo`.
///   - **Opt-in**, like Deep Scan — never runs automatically.
enum AppCleanerService {
    /// Not `private`: `leftoverCandidates` returns this, and it needs to be
    /// nameable from the standalone test harness in `Tests/`, which compiles
    /// straight against this file (see `Tests/run_tests.sh`).
    struct LeftoverKind: Equatable {
        let label: String
        let subtitle: String
    }

    static func listItems() -> [ScanItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))

        var appRoots = ["/Applications"]
        let userApps = home.appendingPathComponent("Applications").path
        if fm.fileExists(atPath: userApps) { appRoots.append(userApps) }

        var items: [ScanItem] = []
        var installedBundleIDs = Set<String>()
        for root in appRoots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appURL = URL(fileURLWithPath: root).appendingPathComponent(entry)
                guard let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier else { continue }
                // Tracked before the Apple/running guards below, so the
                // orphan pass never mistakes a currently-installed Apple or
                // running app's own data for something left behind by an
                // app that's actually gone.
                installedBundleIDs.insert(bundleID)
                guard !bundleID.hasPrefix("com.apple.") else { continue }
                guard !runningBundleIDs.contains(bundleID) else { continue }

                let displayName = (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? appURL.deletingPathExtension().lastPathComponent

                items.append(ScanItem(
                    url: appURL, displayName: displayName, subtitle: "Application",
                    status: .measuring, isDirectory: true, lastAccessed: nil,
                    safety: .caution, removal: .trash))

                for candidate in leftoverCandidates(bundleID: bundleID, displayName: displayName, home: home.path) {
                    guard fm.fileExists(atPath: candidate.path) else { continue }
                    items.append(ScanItem(
                        url: URL(fileURLWithPath: candidate.path),
                        displayName: "\(displayName) — \(candidate.kind.label)",
                        subtitle: candidate.kind.subtitle,
                        status: .measuring, isDirectory: true, lastAccessed: nil,
                        safety: .caution, removal: .trash))
                }
            }
        }
        items += orphanedLeftoverItems(installedBundleIDs: installedBundleIDs, home: home.path)
        return items
    }

    /// The subtitle on every orphan row — deliberately more hedged than a
    /// matched app's leftovers, since there's no installed app to confirm
    /// against: the bundle ID might belong to something removed via
    /// Finder, or to an app installed somewhere this scan doesn't look.
    private static let orphanSubtitle =
        "No installed app matches this bundle ID — likely left behind by an app removed outside DiskSweeper. Review carefully."

    /// Finds leftover data with no installed app to match it — left behind
    /// when an app is dragged to Trash from Finder directly (which only
    /// ever removes the app bundle, never its Preferences/Container/etc.)
    /// rather than through this tool. Reverses the normal direction: instead
    /// of "app → its leftovers," this is "leftover-shaped name → no app
    /// claims it." Deliberately narrower than the installed-app path —
    /// only the locations keyed strictly by bundle ID are checked, never
    /// the name-keyed ones (Application Support/Logs by display name),
    /// since there's no live app to read an exact display name from.
    private static func orphanedLeftoverItems(installedBundleIDs: Set<String>, home: String) -> [ScanItem] {
        let fm = FileManager.default

        func childNames(of dir: String, stripExtension ext: String?) -> Set<String> {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
            guard let ext else { return Set(entries) }
            return Set(entries.compactMap { $0.hasSuffix(".\(ext)") ? String($0.dropLast(ext.count + 1)) : nil })
        }

        let prefsDir = "\(home)/Library/Preferences"
        let savedStateDir = "\(home)/Library/Saved Application State"
        let containersDir = "\(home)/Library/Containers"
        let httpStoragesDir = "\(home)/Library/HTTPStorages"
        let webkitDir = "\(home)/Library/WebKit"

        var found: Set<String> = []
        found.formUnion(childNames(of: prefsDir, stripExtension: "plist"))
        found.formUnion(childNames(of: savedStateDir, stripExtension: "savedState"))
        found.formUnion(childNames(of: containersDir, stripExtension: nil))
        found.formUnion(childNames(of: httpStoragesDir, stripExtension: nil))
        found.formUnion(childNames(of: webkitDir, stripExtension: nil))

        var items: [ScanItem] = []
        for bundleID in orphanBundleIDs(foundNames: found, installedBundleIDs: installedBundleIDs).sorted() {
            let candidates: [(label: String, path: String)] = [
                ("Preferences", "\(prefsDir)/\(bundleID).plist"),
                ("Saved State", "\(savedStateDir)/\(bundleID).savedState"),
                ("Container", "\(containersDir)/\(bundleID)"),
                ("Website Data", "\(httpStoragesDir)/\(bundleID)"),
                ("WebKit Data", "\(webkitDir)/\(bundleID)"),
            ]
            for candidate in candidates {
                guard fm.fileExists(atPath: candidate.path) else { continue }
                items.append(ScanItem(
                    url: URL(fileURLWithPath: candidate.path),
                    displayName: "Orphaned: \(bundleID) — \(candidate.label)",
                    subtitle: orphanSubtitle,
                    status: .measuring, isDirectory: true, lastAccessed: nil,
                    safety: .caution, removal: .trash))
            }
        }
        return items
    }

    /// Pure filter: which found names both look like a real bundle ID
    /// (reverse-DNS shape — at least three dot-separated segments, no
    /// stray characters) and have no currently-installed app claiming
    /// them, directly or by vendor family. Never Apple's own, matched or
    /// not. Pure and file-system-free so it's directly testable.
    static func orphanBundleIDs(foundNames: Set<String>, installedBundleIDs: Set<String>) -> Set<String> {
        let installedVendorPrefixes = Set(installedBundleIDs.compactMap(vendorPrefix))
        return foundNames.filter { name in
            guard looksLikeBundleID(name), !isAppleOwned(name), !installedBundleIDs.contains(name) else { return false }
            // A helper/updater/plugin commonly ships under its own bundle
            // ID rather than its parent app's (e.g. "us.zoom.updater"
            // alongside an installed "us.zoom.xos") — if anything from the
            // same vendor is installed, this is far more likely a live
            // component of it than something actually abandoned, so skip
            // it rather than risk flagging it. Favors missing a real
            // orphan over flagging something still in use.
            if let prefix = vendorPrefix(name), installedVendorPrefixes.contains(prefix) { return false }
            return true
        }
    }

    /// Catches not just literal `com.apple.*` app bundle IDs but Apple's
    /// app-group forms too (`group.com.apple.*`, `systemgroup.com.apple.*`)
    /// — both turned up as real false positives in testing (Mail's group
    /// container, a searchpartyd system-group setting), so this checks for
    /// "com.apple." appearing anywhere, not just as a strict prefix.
    static func isAppleOwned(_ bundleID: String) -> Bool {
        bundleID.range(of: "com.apple.") != nil
    }

    /// The reverse-DNS "vendor" portion — the first two dot-separated
    /// segments, e.g. "us.zoom" from "us.zoom.updater" — shared by an app
    /// and its helper tools/updaters/plugins even when they ship under
    /// distinct bundle IDs from the parent app itself.
    static func vendorPrefix(_ bundleID: String) -> String? {
        let segments = bundleID.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        return segments[0...1].joined(separator: ".")
    }

    static func looksLikeBundleID(_ name: String) -> Bool {
        let segments = name.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 3 else { return false }
        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    /// Every leftover location this app checks, and why each one is safe to
    /// surface — pure and file-system-free, so it's directly testable
    /// against synthetic bundle IDs/names without touching real files.
    static func leftoverCandidates(bundleID: String, displayName: String, home: String)
        -> [(kind: LeftoverKind, path: String)] {
        var candidates: [(kind: LeftoverKind, path: String)] = [
            (LeftoverKind(label: "Preferences", subtitle: "Recreated with defaults if you reinstall"),
             "\(home)/Library/Preferences/\(bundleID).plist"),
            (LeftoverKind(label: "Saved State", subtitle: "Saved window/tab state — recreated automatically"),
             "\(home)/Library/Saved Application State/\(bundleID).savedState"),
            (LeftoverKind(label: "Container", subtitle: "Sandboxed app data — may include your files, review before removing"),
             "\(home)/Library/Containers/\(bundleID)"),
            (LeftoverKind(label: "Application Support", subtitle: "May include your files — review before removing"),
             "\(home)/Library/Application Support/\(bundleID)"),
            (LeftoverKind(label: "Website Data", subtitle: "Cached web data — safe to remove"),
             "\(home)/Library/HTTPStorages/\(bundleID)"),
            (LeftoverKind(label: "WebKit Data", subtitle: "Cached web data — safe to remove"),
             "\(home)/Library/WebKit/\(bundleID)"),
        ]
        // A couple of locations are conventionally keyed by the app's exact
        // display name rather than its bundle ID — still a deterministic,
        // single-candidate lookup, not a search.
        if displayName != bundleID {
            candidates.append(
                (LeftoverKind(label: "Application Support", subtitle: "May include your files — review before removing"),
                 "\(home)/Library/Application Support/\(displayName)"))
            candidates.append(
                (LeftoverKind(label: "Logs", subtitle: "Safe to remove"),
                 "\(home)/Library/Logs/\(displayName)"))
        }
        return candidates
    }
}
