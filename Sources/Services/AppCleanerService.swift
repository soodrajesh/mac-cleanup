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
        for root in appRoots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appURL = URL(fileURLWithPath: root).appendingPathComponent(entry)
                guard let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier else { continue }
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
        return items
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
