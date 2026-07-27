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

// MARK: - Report

if failures == 0 {
    print("PASS — \(checks) checks")
    exit(0)
} else {
    print("\(failures)/\(checks) checks failed")
    exit(1)
}
