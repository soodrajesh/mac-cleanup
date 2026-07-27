import Foundation

/// Category 3: browser **cache** directories only — never history, passwords,
/// bookmarks, or cookies. A missing browser just means its path doesn't
/// exist, so it's silently skipped rather than erroring.
enum BrowserScanService {
    private struct Browser {
        let name: String
        let paths: [String]  // relative to $HOME, may include a `*` profile-glob segment
    }

    private static let browsers: [Browser] = [
        Browser(name: "Safari", paths: ["Library/Caches/com.apple.Safari"]),
        Browser(name: "Chrome", paths: ["Library/Caches/Google/Chrome/*/Cache", "Library/Caches/Google/Chrome/*/Code Cache"]),
        Browser(name: "Firefox", paths: ["Library/Caches/Firefox/Profiles/*/cache2"]),
        Browser(name: "Arc", paths: ["Library/Caches/company.thebrowser.Browser"]),
    ]

    static func listItems() -> [ScanItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var items: [ScanItem] = []

        for browser in browsers {
            for relPath in browser.paths {
                for url in resolve(relPath, under: home) {
                    guard fm.fileExists(atPath: url.path) else { continue }
                    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    items.append(ScanItem(
                        url: url,
                        displayName: "\(browser.name) Cache",
                        subtitle: url.path.replacingOccurrences(of: home.path, with: "~"),
                        status: .measuring,
                        isDirectory: true,
                        lastAccessed: modified,
                        safety: .safe,
                        removal: .trash))
                }
            }
        }
        return items
    }

    /// Expands a single `*` glob segment (e.g. Chrome/Firefox profile folders)
    /// against the filesystem; paths without a glob resolve to themselves.
    private static func resolve(_ relPath: String, under home: URL) -> [URL] {
        guard let starRange = relPath.range(of: "*") else {
            return [home.appendingPathComponent(relPath)]
        }
        let before = String(relPath[relPath.startIndex..<starRange.lowerBound])
        let after = String(relPath[starRange.upperBound...])
        let parentPath = before.hasSuffix("/") ? String(before.dropLast()) : before
        let parent = home.appendingPathComponent(parentPath)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        let suffix = after.hasPrefix("/") ? String(after.dropFirst()) : after
        return children.map { suffix.isEmpty ? $0 : $0.appendingPathComponent(suffix) }
    }
}
