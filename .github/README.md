<div align="center">

# Alive for Mac

**A fast catalog for your Ableton Live projects, plugins and samples, native on macOS.**

An **unofficial macOS port** of [Alive](https://github.com/rueblose/alive) by RueBlose.

![platform](https://img.shields.io/badge/macOS-14%2B-000000)
![arch](https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-native-555555)
![license](https://img.shields.io/badge/license-MIT-blue)

[**Download**](../../releases) · [Features](#features) · [Shortcuts](#keyboard-shortcuts) · [Build](#building-from-source) · [Parity with upstream](../macos/PARITY.md) · **English** · [日本語](README.ja.md)

</div>

---

Alive for Mac reads your Live sets (`.als`) and shows what is inside: tempo, key, plugins, samples,
which version is the latest. It is a Swift/SwiftUI rewrite of the Windows-only original, not a
wrapper. The original C# sources stay in this repository untouched, as the reference for the port.

*Screenshots are to come (the author's own library is not something to publish).*

## Requirements

- macOS 14 (Sonoma) or newer, Apple Silicon or Intel.
- Ableton Live is optional; without it Alive still catalogs your sets, but "Open in Live" is unavailable.

## Install

1. Download `AliveForMac-<version>.zip` from [Releases](../../releases) and unpack it.
2. Move **Alive for Mac.app** to `/Applications`.
3. The app is **ad-hoc signed, not notarized**, so macOS blocks the first launch. Either
   right-click the app → **Open** → **Open**, or run

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Alive for Mac.app"
   ```
4. Press the folder button in the toolbar, point Alive at your Live project folders and press **Scan**.

## Features

- **Home.** Every project is a tile with a picture of its arrangement. Star projects, play the render
  lying next to a set, see your year in Live (active days, streak, record, peak hour).
- **Sets.** Tempo, key, Live version, tracks, plugins, files and project size at a glance. Versions
  (`v1`, `final`, `final 2`) fold into one row. Filters, search, configurable columns, tags and
  notes that belong to the project folder. New sets show up on their own.
- **Plugins.** Audio Units, VST and VST3 in one list: who makes each one, how many sets use it,
  installed or not. Missing plugins are shown as a calm state, never as one error per plugin.
- **Samples.** Which sample folders you actually use and which you never touched, by project.
  Never used, most used, duplicates. Click to audition, drag into Live.
- **Rescue.** A set will not open? Alive reads Live's log and names the plugin it crashed on, or
  finds it by switching plugins off in a copy of the set. The original is never touched.
- **Export.** Collect everything a set needs into one folder or `.zip`, like *Collect All and Save*.
- **Preview and player.** The whole arrangement in Live's clip colours; play the render next to the set.
- **Stat.** Your library as a cloud of dots; choose what axes, size and colour show.
- **English and Japanese**, switchable at runtime (Settings → Language: System / English / 日本語).

## Keyboard shortcuts

| | | | |
|---|---|---|---|
| `⌘1` … `⌘4` | Home / Sets / Plugins / Samples | `⌘O` / `Return` | Open set in Live |
| `⌘5` | Stat window | `⇧⌘R` | Show in Finder |
| `⌘F` | Search | `Space` | Play render or sample |
| `⌥⌘F` | Filters | `⌘Y` | Arrangement preview |
| `⇧⌘O` | Scan folders | `⌘D` | Pin set |
| `⌘R` | Rescan | `⌘T` | Tags and notes |
| `⌘,` | Settings | `⌥⌘R` | Rescue a set |
| `⌘?` | Help | `⌘E` | Export (collect all) |
| `⌃⌘F` / `⌘M` / `⌘Q` | Full screen / minimize / quit | `⌘N` | Launch Live |

On the Samples tab: `←` `→` collapse or expand a folder, `Space` auditions, `Return` opens a folder or
shows a sample in the tree, `⇧Return` reveals it in Finder.

## Data, privacy, what it never does

- Everything Alive remembers lives in `~/Library/Application Support/Alive for Mac` (Settings → Data
  folder). Set the `ALIVE_HOME` environment variable to keep it somewhere else. The file names and
  formats are the original's (`settings.cfg`, `notes.cfg`, `index.cache`, `thumbs/`, ...).
- Alive **never moves or deletes your samples**, and **never modifies your original sets**. Rescue works
  on copies; Export writes to a new folder.
- The only network use is the **opt-in** update check (Settings → Updates): one request to GitHub for the latest
  release of this repository. Nothing about you or your library is sent.

## Building from source

Needs Xcode 15+ or the Swift 5.10 toolchain on macOS 14+. No third-party dependencies.

```sh
cd macos
swift build                 # debug build
swift test                  # unit tests
scripts/build-app.sh        # universal "Alive for Mac.app" in macos/build/ (ad-hoc signed)
scripts/build-app.sh --native   # host architecture only, faster
scripts/build-app.sh --zip      # also macos/dist/AliveForMac-<version>.zip
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

## License and credits

- **Alive** is © RueBlose, MIT licensed: <https://github.com/rueblose/alive>. The original license is
  the root [`LICENSE`](../LICENSE), kept verbatim (and shipped inside the app).
- **Alive for Mac** (everything under `macos/` and `.github/`) is MIT licensed:
  [`macos/LICENSE`](../macos/LICENSE). See also [`macos/NOTICE.md`](../macos/NOTICE.md).
- This is an unofficial port. It is not made, reviewed or endorsed by the original author.
- Ableton and Live are trademarks of Ableton AG. VST is a trademark of Steinberg Media Technologies
  GmbH. Audio Units, macOS and Finder are trademarks of Apple Inc. This project is not affiliated
  with any of them.
