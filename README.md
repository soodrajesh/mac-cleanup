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
- **Trash & Downloads** — current Trash size with its own Empty Trash
  action, and a Downloads review list surfacing files that are old (90+
  days since last use) and/or large (100MB+) — never auto-deleted, always
  reviewed like everything else.

Every scan runs concurrently and sizes items progressively (via `du`,
bounded to a handful of processes at once) so the UI never blocks, even on
a large `DerivedData` folder.

## Layout

```
Sources/
  App.swift, Models.swift, Support.swift
  Services/  SizeCalculator, TrashService, DiskInfoService,
             CacheScanService, DevToolScanService, BrewService,
             DockerService, BrowserScanService, TrashDownloadsService
  Views/     MainView, CategorySectionView, ItemRowView, CLIActionRowView,
             TrashHeaderView, ConfirmDeletionSheet, DeletionProgressView
  Components/ SweepModel, SelectionFooterBar
```

## Ideas for later

Duplicate-file finder, large-file-anywhere-on-disk scanner, language/
localization stripping, app-uninstaller with orphaned-preference cleanup,
iOS backups, Time Machine local snapshots, Mail attachments, a cross-project
`node_modules` sweeper.

## License

MIT
