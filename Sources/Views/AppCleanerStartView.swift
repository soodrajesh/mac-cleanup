import SwiftUI

/// App Cleaner's pre-scan state — explains the safety guarantees up front,
/// since removing an app is a bigger action than clearing a cache.
struct AppCleanerStartView: View {
    @EnvironmentObject var model: SweepModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lists apps in /Applications with their leftover files — Preferences, Saved State, Containers, Application Support, Logs, cached web data — matched to each app's exact bundle ID, never a name guess. Also finds orphaned data (labeled \u{201c}Orphaned:\u{201d}) left behind by apps already removed via Finder, which never touches these locations. Apple's own apps and anything currently running are never shown. Nothing is removed automatically: review each item, then trash what you choose, same as everywhere else. Filter by an app's name — or \u{201c}orphaned\u{201d} — to narrow the list.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Scan Installed Apps…") { model.scan(.appCleaner) }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }
}
