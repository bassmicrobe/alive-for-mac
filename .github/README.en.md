<div align="center">

# Alive for Mac

**A fast, native macOS catalog for your Ableton Live projects, plugins and samples**

An **unofficial macOS port** of [Alive](https://github.com/rueblose/alive) by RueBlose.

![platform](https://img.shields.io/badge/macOS-14%2B-000000)
![arch](https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-universal-555555)
![license](https://img.shields.io/badge/license-MIT-blue)

[**Download**](https://github.com/bassmicrobe/alive-for-mac/releases/latest) · [Install](#install) · [Features](#features) · [Release notes](#release-notes) · [Shortcuts](#keyboard-shortcuts) · [Build](#building-from-source) · [License](#license) · [Parity with upstream](../macos/PARITY.md) · [日本語](README.md) | **English**

</div>

---

Alive for Mac reads your Live sets (`.als`) and shows what is inside: tempo, key, plugins, samples,
which version is the latest. It is a Swift/SwiftUI rewrite of the Windows-only original, not a
wrapper. The original C# sources stay in this repository untouched, as the reference for the port.

## Release notes

### [0.2.1](https://github.com/bassmicrobe/alive-for-mac/releases/tag/v0.2.1) — 2026-10-05 performance and UI/UX improvements

- **Preserve the catalog when a drive is unavailable.** Unreadable project roots keep the previous list and caches. Home and Sets explain the failure, link to folder settings, and clearly indicate when the displayed catalog may be outdated.
- **Faster sample analysis.** Copied-sample matching and folder navigation avoid repeated searches across the library. Duplicate checks respond to rescan cancellation while reading large files.
- **Improve memory use.** Revisiting thumbnails preserves cache memory accounting. Large arrangement previews reduce bitmap resolution while keeping the final tracks visible.
- **Home keyboard navigation.** Arrow keys move selection and focus together. Tile shortcuts respect other buttons and player controls; holding Return or Space avoids repeated actions.
- **Recover from empty search results.** Home, Sets and Plugins provide actions to clear the search or reset filters.
- **Accessibility.** Export switches expose standard actions, clear names and state. Sample and plugin rows, spoken hints, and the Unmute label have also been improved.
- **Plugin discovery and display.** Skip redundant metadata reads for known plugins and keep the final heatmap month caption inside the calendar.

Verified on Apple Silicon / macOS 27.0.1 with 813 tests (zero failures, 10 skipped), a native build,
and Japanese UI checks. In a synthetic fixture with 12,000 equal-size files and 600 copied references,
the previous matching loop took about 2.13 seconds; the new complete usage computation took about
0.013 seconds. This does not measure the improvement for an entire real library.
See the [audit report](../macos/docs/PERFORMANCE_UIUX_AUDIT_2026-10-05.md) for details.

## Requirements

- macOS 14 (Sonoma) or newer. Universal binary: Apple Silicon and Intel.
- Ableton Live is optional; without it Alive still catalogs your sets, but "Open in Live" is unavailable.

## Install

1. Download `AliveForMac-<version>.dmg` from [Releases](https://github.com/bassmicrobe/alive-for-mac/releases/latest).
2. Open the DMG and drag **Alive for Mac** onto the **Applications** folder.
3. Allow the first launch. The app is **ad-hoc signed and not notarized**, so Gatekeeper blocks it the first time.
   - On macOS 15 (Sequoia) and later, right-click → Open no longer bypasses this. Instead:
     1. Try to open **Alive for Mac** from Applications once (it will be blocked).
     2. Open **System Settings → Privacy & Security**, scroll down to the message that "Alive for Mac" was blocked, and press **Open Anyway**.
     3. Confirm in the dialog (password or Touch ID is requested).
   - Advanced alternative: remove the quarantine attribute in Terminal.

     ```sh
     xattr -dr com.apple.quarantine "/Applications/Alive for Mac.app"
     ```
4. Press the folder button in the toolbar, add your Live project folders and press **Scan**.

The DMG also contains the license files (`LICENSE`, `LICENSE-macos`, `NOTICE.md`). A `.zip` of the app is attached to each release as well.

## Features

- **Home.** Every project is a tile with a picture of its arrangement. Star projects, play the render
  lying next to a set, see your year in Live (active days, streak, record, peak hour).
- **Sets.** Tempo, key, Live version, tracks, plugins, files and project size at a glance. Versions
  (`v1`, `final`, `final 2`, ...) fold into one row. Filters, search, configurable columns, and tags and
  notes kept per project. New sets show up on their own.
- **Plugins.** Audio Units, VST and VST3 in one list: who makes each one, how many sets use it,
  installed or not. The list comes from Live's plugin database or from the plugin folders (Settings). Missing plugins are shown as a calm state, never as one error per plugin.
- **Samples.** Which sample folders you actually use and which you never touched, by project.
  Never used, most used, duplicates. Click to audition, drag into Live.
- **Rescue.** If a set will not open, Alive reads Live's log and names the plugin it crashed on, or
  finds it by switching plugins off one by one in a copy of the set. The original is never touched.
- **Export.** Collect everything a set needs into one folder or `.zip`, like *Collect All and Save*.
- **Preview and player.** The whole arrangement in Live's clip colours; play the render next to the set.
- **Stat.** Your library as a cloud of dots; choose what axes, size and colour show.
- **English and Japanese**, switchable at runtime (Settings → Language: System / English / 日本語).

## Keyboard shortcuts

The same list is in the app under Help (`⌘?`).

| | | | |
|---|---|---|---|
| `⌘1` … `⌘4` | Home / Sets / Plugins / Samples | `⌘O` / `Return` | Open set in Live |
| `⌘5` | Stat window | `⇧⌘R` | Show in Finder |
| `⌘F` | Search | `⌥⌘P` | Play / pause render or sample |
| `⌥⌘F` | Filters | `Space` | Play / pause in a focused list |
| `⇧⌘O` | Scan folders | `⌘Y` | Arrangement preview |
| `⌘R` | Rescan | `⌘D` | Pin set |
| `⌘,` | Settings | `⌘T` | Tags and notes |
| `⌘?` | Help | `⌥⌘R` | Rescue a set |
| `⌃⌘F` / `⌘M` / `⌘Q` | Full screen / minimize / quit | `⌘E` | Export (collect all) |
| `⌘N` | Launch Live | | |

On the Samples tab: `←` `→` collapse or expand a folder, `Space` auditions, `Return` opens a folder or
shows a sample in the tree, `⇧Return` reveals it in Finder.

## Data, privacy, what it never does

- Everything Alive remembers lives in `~/Library/Application Support/Alive for Mac` (Settings → Data
  folder). Set the `ALIVE_HOME` environment variable to keep it somewhere else. Tags and notes are in
  `notes.cfg`, settings in `settings.cfg`, the scan result in `index.cache`, thumbnails in `thumbs/`.
  File names and formats are, for the most part, the original's.
- Alive **never modifies your original sets** and **never moves or deletes your samples**. Rescue works
  on copies of the set; Export writes to a new folder (or `.zip`).
- The **only** network use is the update check: one request to GitHub for the latest release of this
  repository, made when you press "Check for updates" in Settings, or once a day if you turn on
  "Check for updates once a day" (off by default). Nothing about you or your library is sent.

## Building from source

A Swift package (`swift-tools-version:5.10`). Verified with Xcode 27 (Swift 6.4); GitHub Actions builds and tests it with the latest stable Xcode on the `macos-26` runner. No third-party dependencies.

```sh
cd macos
swift build                 # debug build
swift test                  # unit tests
scripts/build-app.sh        # universal "Alive for Mac.app" in macos/build/ (ad-hoc signed)
scripts/build-app.sh --native   # host architecture only, faster
scripts/build-app.sh --zip      # also macos/dist/AliveForMac-<version>.zip
scripts/build-app.sh --dmg      # also macos/dist/AliveForMac-<version>.dmg (combine with --zip if you like)
```

`ALIVE_NO_ACTIVATE=1`, `ALIVE_DEBUG_TAB`, `ALIVE_DEBUG_SHEET` and friends (top of
`macos/Sources/AliveUI/App/DebugLaunch.swift`) open a given screen without clicking, for automated
screenshots.

## Following upstream

The port never edits upstream files, so `git merge upstream/main` is always conflict-free. Porting a
change is a tracked step: `macos/scripts/upstream-sync.sh` lists every new upstream commit with the
Swift files it maps to (`macos/upstream-map.tsv`), and a weekly workflow opens an issue when there is
something to port. See [`macos/docs/UPSTREAM.md`](../macos/docs/UPSTREAM.md). What differs from the
original is listed in [`macos/PARITY.md`](../macos/PARITY.md).

## License

This project is a derivative work (a port) of **Alive (by RueBlose)**, which is licensed under the MIT License.

- **The original Alive:** its copyright notice and permission notice are kept unchanged in the root
  [`LICENSE`](../LICENSE).
- **The macOS port** (`macos/` and `.github/`) is under the MIT License in [`macos/LICENSE`](../macos/LICENSE),
  which reproduces the original copyright notice together with the port's own:

  ```text
  Original work — Alive, https://github.com/rueblose/alive
  Copyright (c) 2026

  macOS port — Alive for Mac, https://github.com/bassmicrobe/alive-for-mac
  Copyright (c) 2026 takahashitoru (bassmicrobe)
  ```
- **Shipped with the app:** both license texts and [`macos/NOTICE.md`](../macos/NOTICE.md) are included inside
  the app (`Alive for Mac.app/Contents/Resources/`) and on the DMG, and are shown in the app under
  Settings → About.
- **Third-party code and libraries:** none. Only Apple system frameworks and the system zlib are used.
- **Unofficial:** not made, reviewed or endorsed by the original author, and not affiliated with them.
- **Trademarks:** Ableton, Live, Max for Live and Push are trademarks of Ableton AG. VST is a trademark of
  Steinberg Media Technologies GmbH. Audio Units, macOS and Finder are trademarks of Apple Inc. This
  project is not affiliated with, sponsored by or endorsed by any of them.

## Credits

Thanks to RueBlose and the [Alive](https://github.com/rueblose/alive) project for the excellent original.
