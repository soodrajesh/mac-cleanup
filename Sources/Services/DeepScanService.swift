import Foundation
import UniformTypeIdentifiers

/// Deep Scan — the one category that looks at actual personal content
/// (Documents, Desktop, Pictures, Movies), so unlike everything else it's
/// opt-in: `SweepModel.scanAll()` skips it, a user has to explicitly start
/// it. Flags individual files *and* whole folders at or above the size
/// threshold — a folder made of thousands of small files is exactly as
/// worth surfacing as one big file, and just walking for large files alone
/// would miss it entirely. No age check, since a file sitting in Documents
/// for years is often exactly the one you meant to keep, unlike a stale
/// Downloads item. Every result is `.caution`: never swept up by "Select
/// All Safe".
enum DeepScanService {
    static let sizeThresholdBytes: Int64 = 200 * 1024 * 1024  // 200 MB

    static let defaultRoots = ["Documents", "Desktop", "Pictures", "Movies"]

    static func listItems() -> [ScanItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var items: [ScanItem] = []
        for rootName in defaultRoots {
            let rootURL = home.appendingPathComponent(rootName)
            guard fm.fileExists(atPath: rootURL.path) else { continue }
            items += scan(root: rootURL, label: rootName)
        }
        return items
    }

    /// One `du -a -k` per root returns every file's own size *and* every
    /// directory's cumulative size in a single pass — far cheaper than
    /// walking the tree by hand and `du`-ing each directory individually.
    /// From that size map: bundles/packages (`.app`, `.photoslibrary`, etc.)
    /// are reported as one leaf, never descended into.
    ///
    /// For everything else, a folder is only reported when its *direct*
    /// large children don't already collectively account for ~all of it —
    /// if they do, those children represent it instead and the folder
    /// itself is skipped (drilling down to the specific thing that's
    /// actually big, rather than "Documents (40GB)" merely because
    /// something inside it is). Once a folder *is* reported, none of its
    /// descendants are — a checkbox's size must match exactly what trashing
    /// it would free, so a reported item and anything already nested inside
    /// it can never both appear (that would let selecting both silently
    /// double-report the same bytes).
    private static func scan(root: URL, label: String) -> [ScanItem] {
        guard let sizes = duAll(root) else { return [] }

        let packagePaths = Set(sizes.keys.filter(isPackagePath))
        let excluded = Set(sizes.keys.filter { path in
            packagePaths.contains { pkg in path != pkg && path.hasPrefix(pkg + "/") }
        })
        let hidden = Set(sizes.keys.filter { path in
            path.dropFirst(root.path.count).split(separator: "/").contains { $0.hasPrefix(".") }
        })

        let candidates = sizes.filter { path, size in
            path != root.path && size >= sizeThresholdBytes
                && !excluded.contains(path) && !hidden.contains(path)
        }

        var childSumByParent: [String: Int64] = [:]
        for (path, size) in candidates {
            childSumByParent[(path as NSString).deletingLastPathComponent, default: 0] += size
        }
        func isExplainedByChildren(_ path: String, size: Int64) -> Bool {
            Double(childSumByParent[path] ?? 0) >= Double(size) * 0.9
        }
        func hasReportedAncestor(_ path: String) -> Bool {
            var current = (path as NSString).deletingLastPathComponent
            while current.count > root.path.count {
                if let ancestorSize = candidates[current], !isExplainedByChildren(current, size: ancestorSize) {
                    return true
                }
                current = (current as NSString).deletingLastPathComponent
            }
            return false
        }

        var results: [ScanItem] = []
        for (path, size) in candidates {
            if isExplainedByChildren(path, size: size) { continue }  // children represent it instead
            if hasReportedAncestor(path) { continue }                // an ancestor already represents this whole subtree

            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            results.append(ScanItem(
                url: url,
                displayName: url.lastPathComponent,
                subtitle: "\(label)\(isDir.boolValue ? " · Folder" : "") · \(size.humanBytes)",
                status: .sized(size),
                isDirectory: isDir.boolValue,
                lastAccessed: nil,
                safety: .caution,
                removal: .trash))
        }
        return results
    }

    private static func duAll(_ root: URL) -> [String: Int64]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-a", "-k", root.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        var sizes: [String: Int64] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tabIdx = line.firstIndex(of: "\t") else { continue }
            guard let kb = Int64(line[line.startIndex..<tabIdx]) else { continue }
            sizes[String(line[line.index(after: tabIdx)...])] = kb * 1024
        }
        return sizes
    }

    private static func isPackagePath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .package) || type.conforms(to: .bundle)
    }
}
