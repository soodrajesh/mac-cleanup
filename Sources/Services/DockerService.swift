import Foundation

/// Docker's reclaimable space (dangling images, unused build cache, unused
/// volumes) — managed inside Docker's own VM, not discrete Finder files, so
/// removal goes through `docker ... prune`, not Trash. Only ever prunes
/// dangling/unreferenced resources, never anything a running container uses.
enum DockerService {
    private struct Kind {
        let label: String
        let dfRowPrefix: String
        let pruneArgs: [String]
    }

    private static let kinds: [Kind] = [
        Kind(label: "Dangling Images", dfRowPrefix: "Images", pruneArgs: ["image", "prune", "-f"]),
        Kind(label: "Build Cache", dfRowPrefix: "Build Cache", pruneArgs: ["builder", "prune", "-f"]),
        Kind(label: "Unused Volumes", dfRowPrefix: "Local Volumes", pruneArgs: ["volume", "prune", "-f"]),
    ]

    static func listItems() -> [ScanItem] {
        guard let docker = ToolLocator.find("docker"), let output = run(docker, ["system", "df"]) else { return [] }

        var items: [ScanItem] = []
        for kind in kinds {
            guard let row = output.split(separator: "\n").first(where: { $0.hasPrefix(kind.dfRowPrefix) }) else { continue }
            guard let bytes = reclaimableBytes(fromRow: String(row)), bytes > 0 else { continue }
            items.append(ScanItem(
                url: URL(string: "cli:///docker/\(kind.label)")!,
                displayName: kind.label,
                subtitle: "Reclaimable via docker \(kind.pruneArgs.first ?? "")",
                status: .sized(bytes),
                isDirectory: false,
                lastAccessed: nil,
                safety: .safe,
                removal: .cliNative(toolName: "docker")))
        }
        return items
    }

    /// Runs the prune command matching a listed item's label.
    static func prune(label: String) throws {
        guard let docker = ToolLocator.find("docker"), let kind = kinds.first(where: { $0.label == label }) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: docker)
        process.arguments = kind.pruneArgs
        try process.run()
        process.waitUntilExit()
    }

    private static func run(_ executable: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Parses the RECLAIMABLE column, e.g. "3.1GB (73%)" or "45MB", from a
    /// `docker system df` row.
    private static func reclaimableBytes(fromRow row: String) -> Int64? {
        let fields = row.split(separator: " ", omittingEmptySubsequences: true)
        guard let reclaimableField = fields.last(where: { $0.range(of: #"^[\d.]+[A-Za-z]+$"#, options: .regularExpression) != nil }) else {
            return nil
        }
        return parseHumanSize(String(reclaimableField))
    }

    private static func parseHumanSize(_ s: String) -> Int64? {
        guard let match = s.range(of: #"^([\d.]+)([A-Za-z]+)$"#, options: .regularExpression) else { return nil }
        let matched = String(s[match])
        guard let unitStart = matched.rangeOfCharacter(from: CharacterSet.letters) else { return nil }
        let numberPart = String(matched[matched.startIndex..<unitStart.lowerBound])
        let unitPart = String(matched[unitStart.lowerBound...]).lowercased()
        guard let value = Double(numberPart) else { return nil }

        let multiplier: Double
        switch unitPart {
        case "b":  multiplier = 1
        case "kb": multiplier = 1_000
        case "mb": multiplier = 1_000_000
        case "gb": multiplier = 1_000_000_000
        case "tb": multiplier = 1_000_000_000_000
        default:   return nil
        }
        return Int64(value * multiplier)
    }
}
