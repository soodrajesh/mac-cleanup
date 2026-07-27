import SwiftUI

/// An expandable section for one cleanup category — live-updating total as
/// sizes stream in, "Select All Safe", and the item list. Dev Tool Caches
/// additionally splits out its three CLI-native subsections (simulators,
/// Homebrew, Docker), each with its own action separate from the generic
/// Trash flow.
struct CategorySectionView: View {
    @EnvironmentObject var model: SweepModel
    let category: CleanupCategory

    @AppStorage private var isCollapsed: Bool
    @State private var showSimctlConfirm = false
    @State private var showBrewConfirm = false

    init(category: CleanupCategory) {
        self.category = category
        _isCollapsed = AppStorage(wrappedValue: false, "collapsed.\(category.rawValue)")
    }

    private var result: ScanResult? { model.results[category] }

    private var trashItems: [ScanItem] { (result?.items ?? []).filter { $0.removal == .trash } }
    private var simctlItems: [ScanItem] { (result?.items ?? []).filter { $0.removal == .cliNative(toolName: "simctl") } }
    private var brewItems: [ScanItem] { (result?.items ?? []).filter { $0.removal == .cliNative(toolName: "brew") } }
    private var dockerItems: [ScanItem] { (result?.items ?? []).filter { $0.removal == .cliNative(toolName: "docker") } }
    /// Downloads and Deep Scan are 100% `.caution` by design, so "Select All
    /// Safe" would silently select nothing there — only show it where it
    /// can actually do something.
    private var hasSafeItems: Bool { trashItems.contains { $0.safety == .safe } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !isCollapsed {
                if category == .trash {
                    TrashHeaderView().padding(.leading, 4)
                } else if category == .deepScan && result == nil {
                    DeepScanStartView().padding(.leading, 4)
                } else {
                    VStack(spacing: 0) {
                        if result?.isScanning == true && (result?.items.isEmpty ?? true) {
                            HStack { ProgressView().controlSize(.small); Text("Scanning…").foregroundStyle(.secondary) }
                                .padding(.vertical, 8)
                        } else if trashItems.isEmpty && simctlItems.isEmpty && brewItems.isEmpty && dockerItems.isEmpty {
                            Text("Nothing found").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                        }

                        ForEach(trashItems) { item in
                            ItemRowView(item: item)
                            Divider()
                        }

                        if !simctlItems.isEmpty { simctlSection }
                        if !brewItems.isEmpty { brewSection }
                        if !dockerItems.isEmpty { dockerSection }
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.06)))
    }

    private var header: some View {
        Button {
            isCollapsed.toggle()
        } label: {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Image(systemName: category.symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.rawValue).font(.headline)
                    Text(category.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                // The Trash category has no itemized scan — TrashHeaderView
                // fetches and shows its own real total below.
                if category != .trash, let result {
                    if result.isScanning { ProgressView().controlSize(.small) }
                    Text(result.totalBytes.humanBytes).monospacedDigit().foregroundStyle(.secondary)
                }
                if hasSafeItems {
                    Button("Select All Safe") { model.selectAllSafe(in: category) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                if category == .deepScan && result != nil {
                    Button("Scan Again") { model.scan(.deepScan) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private var simctlSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Unavailable Simulators").font(.subheadline).bold().padding(.top, 6)
            ForEach(simctlItems) { item in
                HStack {
                    Text(item.displayName)
                    Spacer()
                    if case .sized(let bytes) = item.status {
                        Text(bytes.humanBytes).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .font(.callout)
            }
            let totalBytes = simctlItems.reduce(Int64(0)) { $0 + ($1.status.sizeIfKnown ?? 0) }
            Button("Delete \(simctlItems.count) Unavailable Simulator\(simctlItems.count == 1 ? "" : "s")…") {
                showSimctlConfirm = true
            }
            .buttonStyle(.bordered)
            .confirmationDialog(
                "Delete all unavailable simulators?", isPresented: $showSimctlConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { model.deleteUnavailableSimulators() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removed via simctl, not the macOS Trash — frees \(totalBytes.humanBytes), cannot be undone.")
            }
            Divider().padding(.top, 4)
        }
    }

    private var brewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Homebrew Old Versions").font(.subheadline).bold().padding(.top, 6)
            ForEach(brewItems) { item in
                HStack(spacing: 10) {
                    Button {
                        model.toggle(item)
                    } label: {
                        Image(systemName: model.selectedIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(model.selectedIDs.contains(item.id) ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(item.displayName)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if case .sized(let bytes) = item.status {
                        Text(bytes.humanBytes).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .font(.callout)
            }
            let selected = model.selectedBrewItems
            Button(selected.isEmpty ? "Run brew cleanup" : "Run brew cleanup for \(selected.count) selected…") {
                showBrewConfirm = true
            }
            .buttonStyle(.bordered)
            .disabled(selected.isEmpty)
            .confirmationDialog(
                "Run brew cleanup for \(selected.count) formula/cask?", isPresented: $showBrewConfirm, titleVisibility: .visible) {
                Button("Run brew cleanup", role: .destructive) { model.runBrewCleanup() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removed via Homebrew, not the macOS Trash — reinstallable, but cannot be undone by restoring from Trash.")
            }
            Divider().padding(.top, 4)
        }
    }

    private var dockerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Docker").font(.subheadline).bold().padding(.top, 6)
            ForEach(dockerItems) { item in
                CLIActionRowView(item: item) { model.pruneDocker(item) }
            }
        }
    }
}
