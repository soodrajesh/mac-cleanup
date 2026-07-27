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

// MARK: - Report

if failures == 0 {
    print("PASS — \(checks) checks")
    exit(0)
} else {
    print("\(failures)/\(checks) checks failed")
    exit(1)
}
