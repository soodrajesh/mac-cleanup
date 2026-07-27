import SwiftUI

/// Deep Scan's pre-scan state — explains what it covers before doing
/// anything, since it's the one category that reads actual personal content
/// rather than disposable cache, and never runs automatically.
struct DeepScanStartView: View {
    @EnvironmentObject var model: SweepModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recursively looks through \(DeepScanService.defaultRoots.joined(separator: ", ")) for individual files *and* whole folders at or above \(DeepScanService.sizeThresholdBytes.humanBytes) — no age check, since an old file in these folders is often one you meant to keep.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Start Deep Scan…") { model.scan(.deepScan) }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }
}
