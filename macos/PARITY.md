# Alive for Mac — parity with upstream Alive

Where the macOS port stands against [rueblose/alive](https://github.com/rueblose/alive) (Windows, C#),
as of the upstream commit in `UPSTREAM_SYNC`. Written honestly: if it is not listed as **Done**, it
differs. File mapping is in `upstream-map.tsv`; the rules behind the differences are in
`docs/PORTING.md`.

Legend: **Done** = same behaviour · **Simplified** = works, but less than upstream or differently ·
**Mac-only** = not in upstream · **N/A** = does not apply on macOS.

## Features (from upstream's README)

### Home

| Upstream feature | Status | Note |
|---|---|---|
| Project tiles with an arrangement picture | Done | Thumbnails are 480x270 and cached under `thumbs/` with Mac-only cache keys (upstream's cache files are not shared). |
| Star / pin a project | Done | Stored in `home.cfg`. No tag glyph on tiles. |
| Play the render from the tile | Done | Now-playing strip at the bottom of Home. No auto-advance at the end of a render. |
| "Your year in Live" overview (active days, streak, record, peak hour, disk use) | Done | `activity.cache` in the .NET binary layout. |
| Home follows the search box | Done | Home ignores the Sets filters (upstream applies them). |
| Entrance animations | Simplified | Not ported. |
| New Live Set tile | Done | |

### Sets

| Upstream feature | Status | Note |
|---|---|---|
| Sortable list with tempo, key, Live version, tracks, plugins, files, size, place, dates, tags | Done | Native `Table`. Column layout is saved in `sets-columns.json` (not the `setcolumns=` string); hide/reorder through the header context menu; "Reset columns" button. |
| One row per project (versions folded, counter unfolds) | Done | |
| Filters (date, version, key, tracks, plugins, missing files, renders) | Done | Sheet with a count of matching sets; the Filters pill shows the number of active filters. |
| Search | Simplified | Every word must match the set or project name (case, diacritics and width insensitive). Upstream searched 24 columns. |
| Tags and notes (per project folder) | Done | `notes.cfg`. |
| Inspector panel (picture, path, files, plugins, renders, sample folders) | Done | Renders: the newest 6. Sample folders are grouped from the set's own references (User Library / packs / Core Library / sample roots), not through `SampleIndex`. Clicking a folder opens it on the Samples tab. |
| Selection look (white pill) | Simplified | System table selection (grey). Star and play button sit inside the Name cell. |
| New sets appear by themselves | Done | One FSEvents stream (`FolderWatch`), hidden files ignored. |
| Scan folders dialog (project and sample roots) | Done | Roots are applied together with **Scan**. |
| Missing plugins / missing files marks | Done | One aggregated mark per set. Missing plugins are a state, not an error (PORTING rule 11): when Live's installed-plugin list is unavailable nothing is flagged missing and one calm notice says why. |
| Open in Live / Show in Finder | Done | Prefers the newest Live installed. |

### Plugins

| Upstream feature | Status | Note |
|---|---|---|
| Plugin list: vendor, type, format, sets, last used, status | Done | The Type column shows the plugin's own category text (data from the plugin/Live, so it stays English) and falls back to a localized role. Custom list (not `Table`) so a plugin can be scrolled to; columns are not configurable (`pluginColumns` ignored). |
| Summary cards that filter | Done | |
| Plugin filters | Done | |
| Where the list comes from (Live's database or VST folders) | Simplified | The plugin bundles (AU, VST, VST3) are always scanned; Live's scanner log (`PluginScanner.txt`) and `PluginScanDb.txt` are layered on top. "Plugin folders" ignores Live's records. Live's SQLite database is not read. |
| Installed / not installed | Done | Live 11 for Mac has no `PluginScanDb.txt`, so the bundle scan is the truth there. |
| Plugin formats | Mac-only | Audio Units (`.component`) added. VST2 is identified by name only (no binary id), no Mach-O architecture check. Uid form `au:type:subtype:manufacturer`. `PluginScanDb` AU id parsing is a best guess. |
| Show the plugin's sets, jump to a set | Done | |
| Reveal the plugin bundle | Mac-only | ⇧⌘R on the Plugins tab. |

### Samples

| Upstream feature | Status | Note |
|---|---|---|
| Folder tree with usage (by projects) | Done | |
| Never used / Most used / Duplicates | Done | Lenses are pill tabs inside the tab, so the toolbar Filters button is disabled there. |
| Click a sample to hear it | Done | Shared player (`app.audio`): render playback and audition never overlap. `.aifc` added. Waveform through AVFoundation, none for files over 200 MB. |
| Drag a sample into Live | Done | |
| Columns | Simplified | Order and visibility saved in `samplecols`; columns are not resizable. |
| Sample packages / backups | Simplified | Packages count weight only; backups are not scanned. |
| Toolbar counter | Mac-only | "12,923 samples · 23.7 GB" in the toolbar. |
| Reference: ~/Splice | | 12,923 files, 2,219 folders, 23.7 GB: walk 0.6-1.9 s. |

### Rescue

| Upstream feature | Status | Note |
|---|---|---|
| Name the plugin Live crashed on (from Live's log) | Done | Mac log tags, `priorCrashDetected`, `crashDates`; Live's own folder in `~/Library/Preferences/Ableton`. |
| Find the culprit by switching plugins off in a copy | Done | Line-based patching like upstream; the original set is never touched. Probe copies are tracked in `probes.txt` and cleaned up at launch. |
| Audio Unit plugins | Mac-only | Disabling AUs is new (XOR of subtype/manufacturer with `'Aliv'`). **Untested against Live itself.** |
| Detect Live opening | Simplified | Live's process is found through NSWorkspace; manual "It opened / It didn't open" buttons exist as a fallback. `RescueSession.Report` text is not ported. |

### Export (Collect All and Save)

| Upstream feature | Status | Note |
|---|---|---|
| Gather samples, other projects, User Library, packs into a folder | Done | Counts and sizes per group before you start. |
| `.zip` | Simplified | Staged folder + `/usr/bin/ditto` instead of System.IO.Compression. |
| Destination | Simplified | Save panel (default `<project>/<set> Project_export`); an existing destination is refused rather than merged. |
| What gets copied | Stricter (safety) | Only regular media/Live files (or known Live bundles) are copied; anything inside a hidden folder or a sensitive location (Keychains, Mail, browser profiles…) and links leaving the project are refused and listed once in the sheet. Upstream copies whatever a set references, so a crafted set could pull unrelated files into an export. |

### Preview and player

| Upstream feature | Status | Note |
|---|---|---|
| Arrangement preview (whole arrangement in Live's clip colours) | Done | ⌘Y. |
| Player window for the render (seek, volume, waveform) | Done | AVFoundation. |
| Choose which render counts as the main one | Done | `previews.cfg`. |
| Media keys | Done | `MPRemoteCommandCenter`. |

### Stat

| Upstream feature | Status | Note |
|---|---|---|
| Point cloud of the library, mappable axes/size/colour/fade | Done | Rendered with SwiftUI Canvas (no GDI). Palettes and mapping saved in `nebula.cfg`. |
| Look of the dots | Simplified | Antialiased solid dots, no additive glow (it saturated to white). |
| Interaction | Mac-only | Drag inertia, pinch to zoom, right-drag pan; the timeline pauses when idle. |
| One dot per project | Simplified | Versions are folded; error sets and backups are excluded. |
| Inspector next to the cloud | Simplified | Lean built-in inspector (name, picture, path, tags, note, files, plugins, actions). |

### Settings, updates, help

| Upstream feature | Status | Note |
|---|---|---|
| Settings window | Simplified | Standard macOS Settings scene: language, transparency, plugin source, data folder, updates, About. |
| Smooth scrolling | N/A | Native scrolling. The setting is kept in `settings.cfg` for compatibility only. |
| Transparency ("glass") | Done | `NSVisualEffectView` behind the content, off by default. |
| Update check (manual and daily, dot on the gear) | Done | Against `bassmicrobe/alive-for-mac` releases, never upstream's (those are Windows builds). A failed manual check does not stamp `lastupdatecheck`. Opt-in; the only network use. |
| Help overlay (F1) | Done | Help sheet with the Mac shortcut table. |
| Toasts | Done | |
| Link to the developer's Telegram channel | N/A | About links to both GitHub projects instead. |
| UI languages | Mac-only | English and Japanese, switchable at runtime. Upstream has English and Russian. |
| Credits, both licenses, trademark note | Mac-only | Settings → About. |

### Platform plumbing

| Upstream | Status | Note |
|---|---|---|
| Single instance pipe | N/A | macOS opens a second document in the running app. |
| Registry `.als` association | N/A | `NSWorkspace` finds Live. Open from Finder: a set inside a root but not yet in the catalog opens directly in Live; a set outside the roots has its folder added as a root and then gets selected. |
| `%APPDATA%\Alive` | Done | `~/Library/Application Support/Alive for Mac`, or `ALIVE_HOME`. File names and formats kept. |
| Window size and position in `settings.cfg` | Simplified | AppKit frame autosave. Default 1240x780, minimum width 1120. |
| Custom title bar / toolbar | Simplified | Custom top bar under a hidden title bar with native traffic lights. Selected tab = light filled capsule. |
| Keyboard shortcuts | Done | Mac mapping in PORTING §7 (⌘ instead of Ctrl, ⌥⌘F for Filters, ⌘R for Rescan, ...). Same table in Help. |
| App icon | Done | From `icon256.ico` (max 256 px). |

## Data formats

| Item | Status | Note |
|---|---|---|
| `settings.cfg`, `notes.cfg`, `home.cfg`, `previews.cfg`, `nebula.cfg`, `alive.log`, `probes.txt` | Done | Unknown keys round-trip unchanged; Mac-only keys are extra lines (`lang=`, `sets-columns.json` is a separate file). |
| `index.cache`, `activity.cache`, `samples.cache` | Simplified | Written in the .NET `BinaryWriter` layout and tested against hand-verified bytes, but **never verified against a cache written by the real Windows app**. |
| `.als` parsing | Simplified | The whole set is inflated into memory and tokenized by hand (about 11x faster than `XMLParser`; 754 sets in about 8 s on a warm disk). UTF-8 only. AU fields added. Line-based patching for Rescue like upstream. |
| Scanning | Simplified | `concurrentPerform` with max(2, cores) workers (upstream: min(8, cores-1)). A cancelled scan publishes nothing. Symlinks, hidden files, `._*`, `.app`/packages and `Backup` are skipped. File sizes and dates come from `stat(2)` (see tech debt). |
| `ProjectMeta` | Simplified | Unescapes `\n`, not `\r\n`. `Library.cfg` is read oldest to newest. |

## Deviations found while integrating

- A first scan of sets that reference files on an SMB volume took minutes: `FileManager.attributesOfItem`
  also reads extended attributes (about 28 ms per file over SMB). Replaced with `stat(2)` (`FileStat`).
- The sets table crashed ("No Observable object of type AppModel found") when the row set shrank
  (a root removed, a filter applied): table cells no longer read `AppModel` from the SwiftUI environment.
- Samples are scanned quietly in the background at launch (upstream: only when the tab is opened).
- `RescueProbe.cleanupStale` runs before the catalog starts, like upstream's leftover-probe cleanup.
- Hardening after code review (Mac-only, upstream has none of these): inflated `.als` capped at 2 GB
  (decompression bombs), at most 1,024 attributes per XML tag, cache files with impossible counts or
  dates are discarded and rebuilt instead of crashing, a crafted AIFF sample rate can no longer crash the
  sample scan, probe copies never overwrite an existing file (`Name (2).alive-probe.als`) and the
  cleanup only deletes regular files that look like sets, unreadable `settings.cfg`/`notes.cfg`/`home.cfg`
  are backed up to `.bak` before anything is rewritten (UTF-16 and Windows-1252 files from the Windows app
  are read), and `alive.log` writes the home folder as `~`.

## Known gaps / tech debt

- **Rescue for Audio Units has never been run against Live itself.** Treat it as experimental until
  someone has confirmed that Live skips a disabled AU.
- **Caches were never checked against the Windows app** (see Data formats). A cache written by the
  Windows app may be ignored and rebuilt; that is safe but unverified.
- **Duplicated logic:** `Export/CollectScan.swift` (`CollectOrigin`, `CollectDependency`) and
  `Samples/SampleScan.swift` (`SampleOrigin`, `SampleDep`) classify a set's file references in almost
  the same way. Upstream also has two copies (`CollectAll.cs`, `SampleScan.cs`), so they were kept to
  stay diffable; merging them is safe but should be done with both slices' tests.
- Search is narrower than upstream's (names only). No column search.
- VST2 plugins are matched by name only; no architecture (arm64/x86_64) check.
- Live 12's plugin database (SQLite) is not read; on Live 12 the list relies on the bundle scan.
- No notarization: the app is ad-hoc signed, so first launch needs right-click → Open (see the README).
  Sparkle-style in-app updating is not implemented; the update check only opens the release page.
- The Home overview and the Stat window are drawn with Canvas; very large libraries (10,000+ sets) are
  untested.
- `tests` run without a display; the SwiftUI layouts are checked by hand (screenshots) only.
- Screenshots for the README are still to be taken (none are committed: they would show a real library).
