import AppKit
import SwiftUI

extension Color {
    /// A categorical color that steps between light/dark hex values with the
    /// system appearance — used for the fixed-order chart palette so it stays
    /// contrast-correct in both modes without a manual toggle.
    init(light: String, dark: String) {
        self.init(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Int64 {
    var humanBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Date {
    /// "3 days ago", "2 months ago", "just now", etc. — `.named` style reads
    /// naturally for both a scan from minutes ago and one from last week,
    /// where `.numeric` would say the stilted "in 0 seconds".
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var daysAgo: Int {
        Calendar.current.dateComponents([.day], from: self, to: Date()).day ?? 0
    }
}

func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

/// Opens System Settings straight to Full Disk Access — the fix for the
/// overwhelming majority of "couldn't be moved to the trash... you don't
/// have permission" failures this app can produce, so every place that
/// surfaces such a failure can point at the same one-click remedy.
func openFullDiskAccessSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
    NSWorkspace.shared.open(url)
}

extension String {
    /// Heuristic for "this failure is Full Disk Access, not something else
    /// (file in use, already gone)" — macOS's own `trashItem`/`removeItem`
    /// error text for a sandboxed-away path reliably contains "permission"
    /// (e.g. "you don't have permission to access it"), so a substring check
    /// is enough without parsing NSError codes across every failure site.
    var looksLikePermissionError: Bool {
        localizedCaseInsensitiveContains("permission")
    }
}

extension String {
    /// Shared by every filter/search field in the app (category lists, Disk
    /// Report) — plain substring match by default, glob (`*`/`?`) match when
    /// the pattern actually contains a wildcard, so one field handles both
    /// "firefox" and "*.dmg" without the caller needing to choose a mode.
    func matchesFilter(_ pattern: String) -> Bool {
        guard pattern.contains("*") || pattern.contains("?") else {
            return localizedCaseInsensitiveContains(pattern)
        }
        return NSPredicate(format: "SELF LIKE[c] %@", pattern).evaluate(with: self)
    }
}

extension URL {
    /// The full path with the home directory collapsed to `~`, so every
    /// item row can show exactly where a file lives without the noise of a
    /// long absolute path.
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

/// Locates an optional CLI tool by probing the usual Homebrew/manual-install
/// locations, then falling back to `PATH`. Returns nil if not found, so
/// callers can hide the relevant subsection gracefully instead of erroring.
enum ToolLocator {
    static func find(_ name: String) -> String? {
        let candidates = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)", "/bin/\(name)"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return which(name)
    }

    private static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (path?.isEmpty == false) ? path : nil
        } catch {
            return nil
        }
    }
}
