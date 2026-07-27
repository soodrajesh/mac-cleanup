# DiskSweeper

A lightweight macOS disk-cleanup app. Pure Swift + SwiftUI, no Xcode, zero
third-party dependencies. Offline and private — nothing leaves your Mac; it
only runs local commands you can read in `Sources/Services/`.

## Safety model

- **Every deletion goes through macOS Trash** — recoverable until you empty
  it — with one exception below. Nothing is permanently deleted by default.
- **You always review individual items with sizes before anything moves.**
  Scanning never deletes; selection and confirmation are always separate,
  explicit steps.
- **"Select All Safe" only selects regenerable cache items.** Xcode Archives
  and Downloads files are marked `.caution` and are never auto-selected —
  you have to check them yourself.
- **Three CLI-native exceptions, each separately badged and confirmed:**
  unavailable Xcode Simulators (`simctl delete unavailable`), Docker's
  dangling images/build cache/volumes (`docker ... prune`), and Homebrew's
  old formula/cask versions (`brew cleanup`). None of these have a single
  Finder-visible file to move to Trash, or (for Homebrew) the tool manages
  its own version history — so they're removed via their own command, badged
  "not recoverable via Trash," and each has its own confirmation dialog,
  separate from the generic Trash flow.
- **Emptying Trash** is the one place the app uses `removeItem` instead of
  `trashItem` — there's nowhere further to trash Trash's own contents to.
  It gets distinct "this cannot be undone" copy and its own confirmation,
  never bundled into the generic sheet.
- No privileged/root access is needed for anything in this app — every path
  is under your home directory or a user-owned tool cache.

## Prerequisites

- **macOS 13+** and the **Swift toolchain** (`swift --version`) — required
  to build.
- Everything else is optional and auto-detected — if a tool isn't installed,
  its subsection just doesn't appear:
  - `brew`, `docker`, `xcrun`/Xcode Command Line Tools
  - npm, Yarn, pnpm, pip, Poetry (only their cache folders are read, not the
    tools themselves)

## Build & run

```bash
./build.sh
```

`build.sh` compiles the sources, renders the app icon from an SF Symbol,
bundles `DiskSweeper.app`, and installs it to `/Applications`.

```bash
open /Applications/DiskSweeper.app
```

## Features

- **System & App Caches** — `~/Library/Caches/*`, `~/Library/Logs/*`, and
  crash reports, one item per app (resolved to a friendly name where
  possible). Always safe — everything here regenerates on its own.
- **Dev Tool Caches** — Xcode DerivedData (safe) and Archives (review — only
  copy of a build's dSYMs/IPA), CoreSimulator caches, npm/Yarn/pnpm/pip/
  Poetry caches; plus unavailable Simulators, Docker's reclaimable space,
  and Homebrew's old versions as their own CLI-native subsections.
- **Browser Caches** — Safari, Chrome, Firefox, and Arc **cache data only**
  — never history, passwords, bookmarks, or cookies. A browser you don't
  have installed just doesn't show up.
- **Downloads** — a review list surfacing files in `~/Downloads` that are old
  (90+ days since last use) and/or large (100MB+) — never auto-deleted,
  always reviewed like everything else. Its own category, separate from
  Trash.
- **Trash** — current Trash size with its own Empty Trash action. Aggregates
  every Trash location on the Mac (`~/.Trash` plus each volume's root-level
  `/.Trashes/<uid>`), matching what Finder's Trash window shows. Not
  itemized (it's already the safe zone); its own category, separate from
  Downloads.
- **Deep Scan** — the one category that looks at actual personal content:
  recursively scans Documents, Desktop, Pictures, and Movies for individual
  files *and* whole folders at or above 200MB (a folder made of thousands of
  small files is exactly as worth surfacing as one big file). A folder is
  only reported when its large children don't already collectively explain
  ~all of it — otherwise those children are reported instead, drilling down
  to the most specific large item rather than flagging "Documents" merely
  because something inside it is big — and a reported item's descendants are
  never *also* reported, so nothing double-counts. No age check (an old file
  in these folders is often exactly the one you meant to keep), and every
  result is `.caution`. **Opt-in** — unlike every other category, it never
  runs automatically; you start it explicitly from its own section. Its
  results persist across launches (with a "Scanned n ago" timestamp and a
  "Scan Again" button), so reopening the app doesn't mean re-paying the scan
  cost just to see what you already saw.
- **App Cleaner** — lists apps in `/Applications` (and `~/Applications`) with
  their leftover files: Preferences, Saved Application State, Containers,
  Application Support, Logs, and cached web data. Every leftover is matched
  to its app by **exact bundle ID** (or, for the couple of locations
  conventionally keyed by name, the app's exact display name) — never a
  fuzzy or substring search across `~/Library`. Apple's own apps
  (`com.apple.*`) and anything currently running are never listed, so
  there's no path to trashing something mid-use or touching a system app.
  Every path is under `~/Library`/`/Applications` — nothing needs `sudo`.
  Every result is `.caution`, like Deep Scan. **Opt-in**, same as Deep Scan.
- **Filter within a category** — any category with more than a handful of
  items gets a "Filter by name or path" box (most relevant on Deep Scan,
  where results can run long) that narrows the list live as you type.
- **Cross-category selection** — the checkbox selection is one flat set, not
  scoped to whichever tab is open: check items in Downloads, switch to
  Caches, check more, and "Move Selected to Trash" acts on all of it in one
  batch. The footer names which tabs are involved whenever a selection spans
  more than one, so this isn't a hidden capability.

Every item row shows its full path (home-relative, e.g. `~/Downloads/x.zip`)
alongside its size, so you always know exactly where something lives before
deciding on it.

Every scan runs concurrently and sizes items progressively (via `du`,
bounded to a handful of processes at once) so the UI never blocks, even on
a large `DerivedData` folder.

## Navigation

The seven categories live behind a horizontal tab strip rather than one long
stacked list — click a tab, see just that category. Above the tabs, a
collapsible **Overview** panel gives a live-updating snapshot: a single
segmented storage bar showing space by category (a part-to-whole comparison,
which a bar shows more precisely than a pie/donut's arc angles), a legend
with exact sizes, and the 10 largest individually reviewable items across
every category — so the biggest wins are visible without opening each tab
by hand. Colors are assigned in a fixed order per category (never reassigned
or cycled) and are contrast-checked for colorblind-safety in both light and
dark mode. Overview starts expanded (the dashboard you see first) and
auto-collapses to a single line the moment you pick a tab, freeing up room
for that category's content — toggle it back open anytime via its chevron.
Everything (Overview, tabs, and the active category's list) sits in one
continuous scroll, so nothing is ever capped or hidden to force a fit.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘1`–`⌘7` | Jump to a tab (Caches, Dev Tools, Browser, Downloads, Trash, Deep Scan, Apps) |
| `⌘R` | Rescan all categories |
| `⌘⇧A` | Select All Safe in the current tab |
| `⌘⌫` | Move Selected to Trash |

## Testing

The algorithmically interesting logic — Deep Scan's folder-vs-file selection,
Homebrew's formula-name parsing, and App Cleaner's leftover-path lookups —
has regression coverage in `Tests/`, run directly against the real service
files (no XCTest, no Xcode project or SwiftPM package, matching the rest of
this project's `swiftc`-only build):

```bash
Tests/run_tests.sh
```

## Layout

```
Sources/
  App.swift, Models.swift, Support.swift
  Services/  SizeCalculator, TrashService, DiskInfoService,
             CacheScanService, DevToolScanService, BrewService,
             DockerService, BrowserScanService, DownloadsScanService,
             DeepScanService, DeepScanCache, AppCleanerService
  Views/     MainView, OverviewView, CategorySectionView, ItemRowView,
             CLIActionRowView, TrashHeaderView, DeepScanStartView,
             AppCleanerStartView, ConfirmDeletionSheet, DeletionProgressView
  Components/ SweepModel, SelectionFooterBar
```

## Ideas for later

Duplicate-file finder, language/localization stripping, iOS backups, Time
Machine local snapshots, Mail attachments, a cross-project `node_modules`
sweeper, custom user-chosen Deep Scan folders, Group Container matching for
App Cleaner (skipped in the MVP — group IDs don't reliably equal bundle IDs).

## License

MIT
