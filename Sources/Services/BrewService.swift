import Foundation

/// Homebrew's full `brew cleanup` (old formula/cask versions + download
/// cache) — not routed through Trash, since it's Homebrew's own version
/// management, not discrete Finder files a user would recognize. Reviewed
/// per-formula/cask, removed via `brew cleanup <name>` for just the selected
/// ones, badged as CLI-native.
enum BrewService {
    /// One item per formula/cask that `brew cleanup --dry-run` would touch,
    /// sized by summing `du` over the real paths it lists (brew's own
    /// human-readable sizes aren't worth parsing back into bytes).
    static func listItems() -> [ScanItem] {
        guard let brew = ToolLocator.find("brew") else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["cleanup", "--dry-run"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var pathsByName: [String: [String]] = [:]
        for line in output.split(separator: "\n") {
            guard line.hasPrefix("Would remove: ") else { continue }
            let rest = line.dropFirst("Would remove: ".count)
            guard let openParen = rest.lastIndex(of: "(") else { continue }
            let path = rest[rest.startIndex..<openParen].trimmingCharacters(in: .whitespaces)
            guard let name = formulaName(fromPath: path) else { continue }
            pathsByName[name, default: []].append(path)
        }

        return pathsByName.map { name, paths in
            let totalBytes = paths.reduce(Int64(0)) { $0 + (SizeCalculator.size(of: URL(fileURLWithPath: $1)) ?? 0) }
            return ScanItem(
                url: URL(string: "cli:///brew/\(name)")!,
                displayName: name,
                subtitle: "\(paths.count) old version file\(paths.count == 1 ? "" : "s") — reinstallable via brew",
                status: .sized(totalBytes),
                isDirectory: false,
                lastAccessed: nil,
                safety: .safe,
                removal: .cliNative(toolName: "brew"))
        }.sorted { $0.displayName < $1.displayName }
    }

    /// `brew cleanup` scoped to just the selected formula/cask names.
    static func cleanup(formulaNames: [String]) throws {
        guard let brew = ToolLocator.find("brew"), !formulaNames.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["cleanup"] + formulaNames
        try process.run()
        process.waitUntilExit()
    }

    /// `.../Cellar/<formula>/<version>/...` → formula. Cache tarballs are
    /// named `<formula>--<version>...` → the segment before `--`.
    private static func formulaName(fromPath path: String) -> String? {
        let components = path.split(separator: "/")
        if let cellarIdx = components.firstIndex(of: "Cellar"), cellarIdx + 1 < components.count {
            return String(components[cellarIdx + 1])
        }
        if let cellarIdx = components.firstIndex(of: "Caskroom"), cellarIdx + 1 < components.count {
            return String(components[cellarIdx + 1])
        }
        if let filename = components.last, let range = filename.range(of: "--") {
            var name = String(filename[filename.startIndex..<range.lowerBound])
            // Homebrew's own manifest/bottle cache files add a suffix before
            // "--", e.g. "wget_bottle_manifest--1.21.3" — strip it back down
            // to the real formula name so it groups with "wget--1.21.3".
            for suffix in ["_bottle_manifest", "_bottle"] where name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
            }
            return name
        }
        return nil
    }
}
