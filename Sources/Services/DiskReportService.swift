import Foundation

/// Backs the ncdu-style Disk Report tab — unlike every other category this
/// isn't a flat scan-select-delete list, it's read-only drill-down
/// navigation, sized one directory level at a time so opening it never walks
/// the whole home directory up front the way Deep Scan's single big `du`
/// does.
enum DiskReportService {
    struct Entry: Identifiable, Hashable {
        let url: URL
        let sizeBytes: Int64
        let isDirectory: Bool
        var id: URL { url }
    }

    /// `du -d 1 -k` walks each immediate subdirectory's full subtree
    /// internally (that's the only way to know its cumulative size) but only
    /// *emits* one line per subdirectory — so a level is sized lazily, on
    /// descent, rather than the whole tree up front. Immediate *files* at
    /// this level need a separate pass: BSD `du` rejects `-a` combined with
    /// `-d` (`[-a | -s | -d depth]`, mutually exclusive), so per-file sizes
    /// come from a plain `stat` via FileManager instead of a second `du`.
    static func children(of directory: URL) -> [Entry] {
        var entries = subdirectorySizes(of: directory)
        entries += fileSizes(of: directory)
        return entries.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func subdirectorySizes(of directory: URL) -> [Entry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-d", "1", "-k", directory.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        // Discarded, not piped — see SizeCalculator.size(of:) for why an
        // unread stderr pipe can block `du` forever once it hits enough
        // permission-denied entries during the walk.
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return parseDuOutput(output, rootPath: directory.path)
    }

    /// The pure parsing half of `subdirectorySizes`, factored out so it's
    /// directly testable against synthetic `du -d 1 -k` text — no real
    /// filesystem or subprocess needed. Drops the root's own summary line
    /// (its path equals `rootPath` exactly) and any line that doesn't match
    /// `du`'s tab-separated `<kb>\t<path>` shape.
    static func parseDuOutput(_ output: String, rootPath: String) -> [Entry] {
        var entries: [Entry] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tabIdx = line.firstIndex(of: "\t") else { continue }
            guard let kb = Int64(line[line.startIndex..<tabIdx]) else { continue }
            let path = String(line[line.index(after: tabIdx)...])
            guard path != rootPath else { continue }  // root's own summary line, not a child
            entries.append(Entry(url: URL(fileURLWithPath: path), sizeBytes: kb * 1024, isDirectory: true))
        }
        return entries
    }

    private static func fileSizes(of directory: URL) -> [Entry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        var entries: [Entry] = []
        for name in names {
            let url = directory.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let size = (attrs[.size] as? NSNumber)?.int64Value else { continue }
            entries.append(Entry(url: url, sizeBytes: size, isDirectory: false))
        }
        return entries
    }
}
