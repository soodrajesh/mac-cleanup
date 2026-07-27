#!/bin/bash
# Compiles the test harness directly against the real service files (no
# XCTest, no Xcode project/SwiftPM package — matches the rest of this
# project's swiftc-only build) and runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

swiftc -O \
  Tests/main.swift \
  Sources/Models.swift \
  Sources/Support.swift \
  Sources/Services/SizeCalculator.swift \
  Sources/Services/BrewService.swift \
  Sources/Services/DeepScanService.swift \
  Sources/Services/AppCleanerService.swift \
  -o /tmp/disksweeper-tests

/tmp/disksweeper-tests
