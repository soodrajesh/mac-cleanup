import Foundation

/// Category 2: Xcode caches, package manager caches, and simulator device
/// data. Combined with BrewService and DockerService (their CLI-native items
/// merge into this same category) by SweepModel.
enum DevToolScanService {
    static func listItems() -> [ScanItem] {
        var items: [ScanItem] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // Xcode DerivedData — safe, fully regenerable by rebuilding.
        addIfExists(home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                    name: "Xcode DerivedData", subtitle: "Rebuilds automatically on next build",
                    safety: .safe, to: &items)

        // Xcode Archives — the only copy of a build's dSYMs/IPA. Never regenerable.
        addIfExists(home.appendingPathComponent("Library/Developer/Xcode/Archives"),
                    name: "Xcode Archives", subtitle: "Only copy of past build archives — review carefully",
                    safety: .caution, to: &items)

        // CoreSimulator's own cache (distinct from per-device data below).
        addIfExists(home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"),
                    name: "Simulator Caches", subtitle: "Regenerable simulator runtime caches",
                    safety: .safe, to: &items)

        // Package manager caches — each only added if the tool/its cache exists.
        addIfExists(home.appendingPathComponent(".npm"), name: "npm Cache", subtitle: "~/.npm", safety: .safe, to: &items)
        addIfExists(home.appendingPathComponent("Library/Caches/Yarn"), name: "Yarn Cache", subtitle: "~/Library/Caches/Yarn", safety: .safe, to: &items)
        addIfExists(home.appendingPathComponent("Library/pnpm/store"), name: "pnpm Store", subtitle: "~/Library/pnpm/store", safety: .safe, to: &items)
        addIfExists(home.appendingPathComponent("Library/Caches/pip"), name: "pip Cache", subtitle: "~/Library/Caches/pip", safety: .safe, to: &items)
        addIfExists(home.appendingPathComponent("Library/Caches/pypoetry"), name: "Poetry Cache", subtitle: "~/Library/Caches/pypoetry", safety: .safe, to: &items)

        items.append(contentsOf: unavailableSimulators())
        return items
    }

    private static func addIfExists(_ url: URL, name: String, subtitle: String, safety: SafetyLevel, to items: inout [ScanItem]) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        items.append(ScanItem(
            url: url, displayName: name, subtitle: subtitle, status: .measuring,
            isDirectory: true, lastAccessed: nil, safety: safety, removal: .trash))
    }

    /// Unavailable simulator devices (deleted runtime, but the device's data
    /// directory lingers). Real per-device directories, but removed via
    /// `simctl delete unavailable` rather than Trash, since that command
    /// also cleans up simctl's own device registry, not just the files.
    private static func unavailableSimulators() -> [ScanItem] {
        guard let xcrun = ToolLocator.find("xcrun") else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrun)
        process.arguments = ["simctl", "list", "devices", "unavailable", "-j"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let devicesByRuntime = json["devices"] as? [String: Any] else { return [] }

            let devicesRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Developer/CoreSimulator/Devices")

            var items: [ScanItem] = []
            for (runtime, devices) in devicesByRuntime {
                guard let list = devices as? [[String: Any]] else { continue }
                for device in list {
                    guard let udid = device["udid"] as? String, let name = device["name"] as? String else { continue }
                    let deviceDir = devicesRoot.appendingPathComponent(udid)
                    guard FileManager.default.fileExists(atPath: deviceDir.path) else { continue }
                    items.append(ScanItem(
                        url: deviceDir,
                        displayName: "\(name) (unavailable)",
                        subtitle: runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: ""),
                        status: .measuring,
                        isDirectory: true,
                        lastAccessed: nil,
                        safety: .safe,
                        removal: .cliNative(toolName: "simctl")))
                }
            }
            return items
        } catch {
            return []
        }
    }

    /// Removes all unavailable simulators via `simctl delete unavailable` —
    /// a single command for the whole set, matching how simctl manages its
    /// own device registry (not a per-item Trash operation).
    static func deleteUnavailableSimulators() throws {
        guard let xcrun = ToolLocator.find("xcrun") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrun)
        process.arguments = ["simctl", "delete", "unavailable"]
        try process.run()
        process.waitUntilExit()
    }
}
