import Foundation

/// A standalone regression harness for the two algorithmically interesting
/// pieces of logic in the app — Deep Scan's "explained by children" folder
/// selection, and Homebrew's formula-name parsing. Not XCTest: the project
/// has no Xcode project or SwiftPM package (deliberately, per the sibling
/// apps' house style), so this compiles straight against the real service
/// files via `swiftc` (see `run_tests.sh`) and asserts with plain `print`.

var failures = 0
var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL: \(label)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    expect(actual == expected, "\(label) — got \(actual), expected \(expected)")
}

func expectSet(_ actual: [String], _ expected: Set<String>, _ label: String) {
    expectEqual(Set(actual), expected, label)
}

// MARK: - DeepScanService.selectCandidates

let t = DeepScanService.sizeThresholdBytes

do {
    // A folder whose direct large children collectively explain ~all of it
    // is skipped in favor of reporting the children themselves.
    let sizes: [String: Int64] = [
        "/root": t * 10,
        "/root/A": t * 5,
        "/root/A/x": t * 5 / 2,
        "/root/A/y": t * 5 / 2,
    ]
    let result = DeepScanService.selectCandidates(sizes: sizes, rootPath: "/root")
    expectSet(result, ["/root/A/x", "/root/A/y"], "folder explained by children → children reported, not the folder")
}

do {
    // A folder whose large-enough total isn't explained by any individually
    // large children (they're all below threshold) is reported itself.
    let sizes: [String: Int64] = [
        "/root": t * 10,
        "/root/B": t * 2,
        "/root/B/tiny1": t / 4,
        "/root/B/tiny2": t / 4,
    ]
    let result = DeepScanService.selectCandidates(sizes: sizes, rootPath: "/root")
    expectSet(result, ["/root/B"], "folder not explained by (sub-threshold) children → folder itself reported")
}

do {
    // A reported ancestor must exclude a large descendant even when an
    // intermediate directory in between is itself "explained away" — this
    // is the double-counting bug caught before shipping Deep Scan.
    let sizes: [String: Int64] = [
        "/root": t * 20,
        "/root/C": t * 9,
        "/root/C/other": t / 10,
        "/root/C/sub": t * 3,
        "/root/C/sub/E": t * 3 * 9 / 10,  // 90% of sub's size → sub is "explained", doesn't itself block
    ]
    let result = DeepScanService.selectCandidates(sizes: sizes, rootPath: "/root")
    expectSet(result, ["/root/C"], "reported ancestor excludes nested descendant even through an explained intermediate dir")
}

do {
    // Nothing below threshold is ever a candidate, regardless of nesting.
    let sizes: [String: Int64] = [
        "/root": t * 2,
        "/root/small": t / 2,
    ]
    let result = DeepScanService.selectCandidates(sizes: sizes, rootPath: "/root")
    expectEqual(result, [], "sub-threshold items are never reported")
}

// MARK: - BrewService.formulaName(fromPath:)

expectEqual(BrewService.formulaName(fromPath: "/opt/homebrew/Cellar/wget/1.21.3/somefile"),
            "wget", "Cellar path → formula name")
expectEqual(BrewService.formulaName(fromPath: "/opt/homebrew/Caskroom/some-cask/1.0/somefile"),
            "some-cask", "Caskroom path → cask name")
expectEqual(BrewService.formulaName(fromPath: "/opt/homebrew/Cache/wget--1.21.3.tar.gz"),
            "wget", "cache tarball → name before --")
expectEqual(BrewService.formulaName(fromPath: "/opt/homebrew/Cache/wget_bottle_manifest--1.21.3.json"),
            "wget", "manifest cache file → _bottle_manifest suffix stripped, groups with wget")
expectEqual(BrewService.formulaName(fromPath: "/opt/homebrew/Cache/wget_bottle--1.21.3"),
            "wget", "bottle cache file → _bottle suffix stripped, groups with wget")
expectEqual(BrewService.formulaName(fromPath: "/some/random/path/file.txt"),
            nil, "no Cellar/Caskroom and no -- separator → unrecognized, nil")

// MARK: - AppCleanerService.leftoverCandidates

do {
    // Exact bundle-ID lookups only — every path is deterministic, no
    // fuzzy/substring search across ~/Library.
    let candidates = AppCleanerService.leftoverCandidates(
        bundleID: "com.example.Widget", displayName: "Widget", home: "/Users/x")
    let paths = candidates.map(\.path)
    expect(paths.contains("/Users/x/Library/Preferences/com.example.Widget.plist"),
           "Preferences path keyed by exact bundle ID")
    expect(paths.contains("/Users/x/Library/Containers/com.example.Widget"),
           "Container path keyed by exact bundle ID")
    expect(paths.contains("/Users/x/Library/Application Support/Widget"),
           "Application Support also checked under the exact display name")
    expect(paths.contains("/Users/x/Library/Logs/Widget"),
           "Logs path keyed by exact display name")
    expectEqual(paths.count, Set(paths).count, "no duplicate candidate paths")
}

do {
    // When the display name equals the bundle ID there's nothing distinct
    // to key the name-based locations by — those two candidates should be
    // skipped rather than duplicating the bundle-ID-keyed ones.
    let candidates = AppCleanerService.leftoverCandidates(
        bundleID: "Widget", displayName: "Widget", home: "/Users/x")
    let paths = candidates.map(\.path)
    expect(!paths.contains("/Users/x/Library/Logs/Widget"),
           "name-keyed Logs candidate skipped when name == bundle ID")
    expectEqual(paths.count, Set(paths).count, "still no duplicate candidate paths")
}

// MARK: - AppCleanerService orphan detection

expect(AppCleanerService.looksLikeBundleID("com.example.Widget"), "three-segment reverse-DNS name looks like a bundle ID")
expect(AppCleanerService.looksLikeBundleID("com.example.sub.Widget"), "more than three segments still looks like a bundle ID")
expect(!AppCleanerService.looksLikeBundleID("Widget"), "a bare name has no dots — not bundle-ID-shaped")
expect(!AppCleanerService.looksLikeBundleID("com.example"), "only two segments — too short to be a real bundle ID")
expect(!AppCleanerService.looksLikeBundleID("com..example.Widget"), "an empty segment (double dot) is rejected")
expect(!AppCleanerService.looksLikeBundleID("com.example.Wid get"), "a space isn't a valid bundle ID character")
expect(AppCleanerService.looksLikeBundleID("com.example-corp.My_Widget"), "hyphens and underscores are valid within a segment")

do {
    let found: Set<String> = [
        "com.adobe.OldApp",          // not installed, bundle-ID-shaped → orphan
        "com.example.StillHere",     // installed → not an orphan
        "com.apple.something",       // Apple's own → never flagged, even if not installed
        "TemporaryItems",            // not bundle-ID-shaped → ignored
        "com.example",               // too short → ignored
    ]
    let installed: Set<String> = ["com.example.StillHere"]
    let orphans = AppCleanerService.orphanBundleIDs(foundNames: found, installedBundleIDs: installed)
    expectEqual(orphans, ["com.adobe.OldApp"], "only the not-installed, bundle-ID-shaped, non-Apple name is flagged as orphaned")
}

// Real false positives caught during manual testing: Apple's app-group
// forms (not just a literal "com.apple." prefix) and vendor-family helper
// tools of an app that's still installed.
expect(AppCleanerService.isAppleOwned("group.com.apple.mail"), "an app-group container for Mail is still Apple-owned")
expect(AppCleanerService.isAppleOwned("systemgroup.com.apple.icloud.searchpartyd.sharedsettings"),
       "a systemgroup setting is still Apple-owned")
expect(AppCleanerService.isAppleOwned("com.apple.Safari"), "a plain com.apple.* bundle ID is still caught")
expect(!AppCleanerService.isAppleOwned("com.adobe.OldApp"), "a genuinely non-Apple bundle ID is not flagged as Apple's")

expectEqual(AppCleanerService.vendorPrefix("us.zoom.updater"), "us.zoom", "vendor prefix is the first two segments")
expectEqual(AppCleanerService.vendorPrefix("us.zoom.us.xos"), "us.zoom", "still just the first two segments, even with more after")
expectEqual(AppCleanerService.vendorPrefix("com"), nil, "a single segment has no vendor prefix")

do {
    let found: Set<String> = [
        "group.com.apple.mail",                                    // Apple app-group → never flagged
        "systemgroup.com.apple.icloud.searchpartyd.sharedsettings", // Apple systemgroup → never flagged
        "us.zoom.updater",                                          // shares "us.zoom" with an installed app → skipped
        "com.adobe.TrulyGoneApp",                                   // no installed app shares its vendor → real orphan
    ]
    let installed: Set<String> = ["us.zoom.xos"]  // the main Zoom app, not the updater helper's own bundle ID
    let orphans = AppCleanerService.orphanBundleIDs(foundNames: found, installedBundleIDs: installed)
    expectEqual(orphans, ["com.adobe.TrulyGoneApp"],
                "Apple app-groups and an installed app's own helper tools are excluded; only the true orphan remains")
}

// MARK: - SizeCalculator timeout guard

do {
    // A deadline that's already effectively expired must still return nil
    // rather than hang or crash — this is what actually proves the watchdog
    // terminates the process, not just that the parameter is accepted.
    // `/System` is large enough that `du` can't possibly finish inside 1ms,
    // so the race is deterministic in the timeout's favor.
    let start = Date()
    let result = SizeCalculator.size(of: URL(fileURLWithPath: "/System"), timeoutSeconds: 0.001)
    let elapsed = Date().timeIntervalSince(start)
    expect(result == nil, "an expired timeout returns nil instead of the real (much larger) size")
    expect(elapsed < 5, "a timed-out call returns promptly rather than hanging")
}

do {
    // A normal, fast, valid path still sizes correctly under a real timeout.
    let result = SizeCalculator.size(of: URL(fileURLWithPath: NSTemporaryDirectory()))
    expect(result != nil, "a normal path still sizes correctly with the default timeout")
}

// MARK: - TrashService.shouldThrowAccessDenied

expect(!TrashService.shouldThrowAccessDenied(existingCount: 0, deniedCount: 0),
       "nothing exists yet → not an error, just nothing to report")
expect(!TrashService.shouldThrowAccessDenied(existingCount: 2, deniedCount: 0),
       "everything readable → not an error")
expect(!TrashService.shouldThrowAccessDenied(existingCount: 2, deniedCount: 1),
       "only some roots denied → the readable ones still count, not an error")
expect(TrashService.shouldThrowAccessDenied(existingCount: 2, deniedCount: 2),
       "every existing root denied → genuinely can't tell, this is an error")
expect(TrashService.shouldThrowAccessDenied(existingCount: 1, deniedCount: 1),
       "the single existing root denied → an error")

// MARK: - DiskReportService.parseDuOutput

do {
    // `du -d 1 -k` output: root's own summary line first, then one line
    // per immediate child — root path must be dropped, children kept.
    let output = "20480\t/Users/x/Documents\n8192\t/Users/x/Documents/Photos\n4096\t/Users/x/Documents/Notes\n"
    let entries = DiskReportService.parseDuOutput(output, rootPath: "/Users/x/Documents")
    expectEqual(entries.count, 2, "root's own summary line is dropped, only children remain")
    expect(entries.contains { $0.url.path == "/Users/x/Documents/Photos" && $0.sizeBytes == 8192 * 1024 },
           "child size is kb → bytes converted correctly")
    expect(entries.allSatisfy(\.isDirectory), "every parsed entry is marked a directory (this is the -d 1 subdirectory pass)")
}

do {
    // A line with no tab (malformed/unexpected `du` output) is skipped
    // rather than crashing or producing a garbage entry.
    let output = "not a valid du line\n4096\t/Users/x/Documents/Notes\n"
    let entries = DiskReportService.parseDuOutput(output, rootPath: "/Users/x/Documents")
    expectEqual(entries.count, 1, "malformed line is skipped, well-formed one still parses")
}

expectEqual(DiskReportService.parseDuOutput("", rootPath: "/Users/x"), [], "empty output → no entries")

// MARK: - Report

if failures == 0 {
    print("PASS — \(checks) checks")
    exit(0)
} else {
    print("\(failures)/\(checks) checks failed")
    exit(1)
}
