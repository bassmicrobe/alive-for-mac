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
| Project tiles with an arrangement picture | Done | Thumbnails are 480x270 and cached under `thumbs/` with Mac-only cache keys (upstream's cache files are not shared). Bar lines and ruler numbers count the set's own bars (its time signature); pictures already in `thumbs/` keep the old grid until the set is saved again (the cache key is the set's modification time). The picture of the previous set is never shown for the next one. |
| Star / pin a project | Done | Stored in `home.cfg`. No tag glyph on tiles. The star filter is hidden while no pinned project matches the search. |
| Play the render from the tile | Done | Now-playing strip at the bottom of Home. No auto-advance at the end of a render. |
| "Your year in Live" overview (active days, streak, record, peak hour, disk use) | Done | `activity.cache` in the .NET binary layout, with the project folder of each save behind the moments (`proj` tail; only written once a save has a folder). Clicking a day lists the projects saved that day, busiest first, as a popover (upstream: a context menu); picking one jumps to its tile. A day saved before folders were kept shows "Projects were not recorded that day". |
| Home follows the search box | Done | Same rule as Sets (below). Home ignores the Sets filters (upstream applies them). A search that hides the selected tile clears the selection. "1 project shown" / "12 projects shown". |
| Keyboard in the grid | Done | ↓ in the search field goes on into the tiles; Home / End: first / last tile. |
| Entrance animations | Simplified | Not ported. |
| New Live Set tile | Done | |
| Random project (die button) | Simplified | No die button; `alive://random` picks one. The icon constant is `dice3`, as upstream. |
| Tile text fades with the tile | N/A | SwiftUI opacity already covers the text. |

### Sets

| Upstream feature | Status | Note |
|---|---|---|
| Sortable list with tempo, key, Live version, tracks, plugins, files, size, place, dates, tags | Done | Native `Table`. Column layout is saved in `sets-columns.json` (not the `setcolumns=` string); hide/reorder through the header context menu; "Reset columns" button. |
| One row per project (versions folded, counter unfolds) | Done | |
| Filters (date, version, key, tracks, plugins, missing files, renders) | Done | Sheet with a count of matching sets; the Filters pill shows the number of active filters. |
| Search | Done | One rule for Home and Sets (`SetFilter.matchesSearch`): name, project, path, plugins, renders, tags and note. Mac addition: every whitespace-separated word must hit some field (upstream: the whole phrase in one field), and case, diacritics and full/half width are ignored. No per-column search. ↓ in the search field goes on into the list. |
| Tags and notes (per project folder) | Done | `notes.cfg`. |
| Inspector panel (picture, path, files, plugins, renders, sample folders) | Done | Renders: the newest 6. Sample folders are grouped from the set's own references (User Library / packs / Core Library / sample roots), not through `SampleIndex`. Clicking a folder opens it on the Samples tab. |
| Selection look (white pill) | Simplified | System table selection (grey). Star and play button sit inside the Name cell. |
| New sets appear by themselves | Done | One FSEvents stream (`FolderWatch`), hidden files ignored. |
| Scan folders dialog (project and sample roots) | Done | Roots are applied together with **Scan**. |
| Missing plugins / missing files marks | Done | One aggregated mark per set. Missing plugins are a state, not an error (PORTING rule 11): when Live's installed-plugin list is unavailable nothing is flagged missing and one calm notice says why. |
| Open in Live / Show in Finder | Done | Prefers the newest Live installed. |
| Filter calendar (date fields) | Simplified | A SwiftUI month grid with the keyboard (arrows, Page Up / Down, Home / End, Return); the graphical `DatePicker` always paints one day as picked, so an empty field could not show "nothing picked". Week start and month names follow the app language (upstream forces Monday / English). |
| Counters and lists | Done | The Filters counter counts the list's rows (projects when versions are folded), with singular forms ("1 project matches"). "Pinned first" is hidden while no row is pinned. Two versions saved on one day show their time. Home / End: first / last row. Copy path (row menu); the Plugins heading of the inspector copies the set's plugin list as text ("Installed:" / "Missing:" headings follow the app language). |

### Plugins

| Upstream feature | Status | Note |
|---|---|---|
| Plugin list: vendor, type, format, sets, last used, status | Done | The Type column shows the plugin's own category text (data from the plugin/Live, so it stays English) and falls back to a localized role. Custom list (not `Table`) so a plugin can be scrolled to; columns are not configurable (`pluginColumns` ignored). |
| Summary cards that filter | Done | |
| Plugin filters | Done | |
| Where the list comes from (Live's database or VST folders) | Simplified | The plugin bundles (AU, VST, VST3) are always scanned; Live's scanner log (`PluginScanner.txt`) and `PluginScanDb.txt` are layered on top. "Plugin folders" ignores Live's records. Live's SQLite database is not read. |
| Installed / not installed | Done | Live 11 for Mac has no `PluginScanDb.txt`, so the bundle scan is the truth there. |
| Plugin formats | Mac-only | Audio Units (`.component`) added. VST2 is identified by name only (no binary id), no Mach-O architecture check. Uid form `au:type:subtype:manufacturer`. `PluginScanDb` AU id parsing is a best guess. |
| Show the plugin's sets, jump to a set | Done | Space on the Plugins tab pauses / resumes the player when it has something loaded; Home / End: first / last plugin; ↓ in the search field goes on into the list. |
| Reveal the plugin bundle | Mac-only | ⇧⌘R on the Plugins tab. |

### Samples

| Upstream feature | Status | Note |
|---|---|---|
| Folder tree with usage (by projects) | Done | |
| Never used / Most used / Duplicates | Done | Lenses are pill tabs inside the tab, so the toolbar Filters button is disabled there. |
| Click a sample to hear it | Done | Shared player (`app.audio`): render playback and audition never overlap. `.aifc` added. Waveform through AVFoundation, none for files over 200 MB. `→` plays from the start (Space still toggles), a press on empty space stops the sample (never a render), and a volume slider under the wave sets the audition level (`previewvolume`; it does not touch the render player's volume). A waveform that cannot be read (busy, cut short) is logged and shows what was read. |
| Sample library at start | Simplified | The cached library shows at once; the folders are walked in the background only when the last whole walk is over a day old or a switched-on folder is missing from the cache (the time of the walk is kept behind the roots of `samples.cache`). F5, a new folder and a returning volume always walk. |
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
| Destination | Simplified | Save panel (default `<project>/<set> Project_export`); an existing destination is refused rather than merged. After a copy with failures the toast names `alive.log` and Finder reveals the log instead of the output. |
| What gets copied | Stricter (safety) | Only regular media/Live files (or known Live bundles) are copied; anything inside a hidden folder or a sensitive location (Keychains, Mail, browser profiles…) and links leaving the project are refused and listed once in the sheet. Upstream copies whatever a set references, so a crafted set could pull unrelated files into an export. |

### Preview and player

| Upstream feature | Status | Note |
|---|---|---|
| Arrangement preview (whole arrangement in Live's clip colours) | Done | ⌘Y. Track names without clip captions; a track is never lower than its name and many tracks scroll. Moved about as in Live: wheel = tracks, ⇧ wheel = time, ⌘ wheel (Ctrl upstream) = zoom around the pointer, ⌥ wheel (Alt) = track height, middle-button drag = move; Mac-only: pinch zooms, a two-finger sideways swipe scrolls the time, `+` `-` `0` zoom. The old 1x..32x steps and the "taller tracks" toggle are gone (continuous zoom). Bars are counted in the set's own time signature; "1 bar / 1 track / 1 clip". |
| Player window for the render (seek, volume, waveform) | Done | AVFoundation. ⇧↩ shows the selected render (else the current one) in Finder, also in the row's menu ("Show in Finder"). |
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
| Window size and catalog | Done | The window grows with the interface scale (never beyond the screen). Stat shows the main window's catalog and follows each rescan; ⌘R in Stat always rescans the catalog. "1 project" in the status line. |

### Settings, updates, help

| Upstream feature | Status | Note |
|---|---|---|
| Settings window | Simplified | Standard macOS Settings scene: language, interface scale, transparency, plugin source, data folder, updates, About. |
| Interface scale (75 / 100 / 125 %) | Done | Applies at once (upstream: after a restart). Every `Theme` size and font follows it, and the sheets, tabs, pills, cards, toasts, top bar, Help and Settings with them; about 300 literal `.frame` / `.padding` numbers in views are not scaled yet (see Deviations). The preview canvas draws at the display's scale only. |
| Smooth scrolling | N/A | Native scrolling. The setting is kept in `settings.cfg` for compatibility only. |
| Transparency ("glass") | Done | `NSVisualEffectView` behind the content, off by default. |
| Update check (manual and daily, dot on the gear) | Done | Against `bassmicrobe/alive-for-mac` releases, never upstream's (those are Windows builds). A failed manual check does not stamp `lastupdatecheck`. Opt-in; the only network use. |
| Help overlay (F1) | Done | Help sheet with the Mac shortcut table, in two columns; the card is as tall as its content and scrolls only when the window is too low. F11 stays ⌃⌘F (full screen). |
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

## Mac-only additions

None of these exist in upstream. They are additive: upstream's files and formats are unchanged (new
data lives in separate files, see below).

| Feature | Note |
|---|---|
| Set readiness ("Ready to open") | A Sets filter and an inspector line: every referenced file found, every plugin installed, no drive missing. Precedence: can't be read (the .als did not parse: never ready), files missing, plugins missing, drive offline, plugin status unknown, ready. |
| Offline volumes | A path under an unmounted `/Volumes/<X>` is *offline*, not missing: its own wording on sets and sample roots, updated on mount/unmount without a rescan. A project root that no longer exists is reported as "Folder not found" with *Choose again* / *Remove*. |
| Stale render | A set saved more than two minutes after its newest render is marked; also a Sets filter. |
| Launch diff scan | At launch a local root is brought up to date from the FSEvents journal (`scan-history.cfg`) instead of a full walk; network volumes, external or removable drives (event ids are host-global), an old or untrusted journal, a catalog that is not the one the checkpoint was taken with, and every explicit rescan fall back to a full scan. The checkpoint is saved only after `index.cache` and `status.cache` were; a changed folder that cannot be listed keeps its rows and the root is walked in full next time. |
| Spotlight search | Sets are donated to Core Spotlight (name, tempo, key, plugins, tags). The items are app-donated: they appear in the system search (⌘Space), **not** in `mdfind`. On by default (Settings, "Mac 連携"). Switching it off deletes Alive's items from Spotlight (the whole domain, once per launch, whether or not a local snapshot exists). |
| Menu bar extra | Today's saves, streak, pinned and recent projects, now playing. On by default. |
| Finder tags | Opt-in, off by default: Alive tags are written to the project folder as Finder tags (merged with the user's own; only tags Alive added are removed again). This changes project folders, which Dropbox / iCloud sync. |
| Quick Look preview | Space on an `.als` in Finder shows the arrangement and the set's details. Needs **one-time enabling** (Settings, "Quick Look とウィジェット", then *Enable*). |
| Desktop widget | Streak, activity heatmap and recent sets. Needs **one-time enabling** (right-click the desktop, Edit Widgets, Alive). It reads `widget/widget.json` from the default data folder only: with a custom `ALIVE_HOME` it shows its placeholder. |
| `alive://` URL scheme | `home`, `sets?q=`, `open?path=`, `latest`, `random`, `rescan`, `samples?q=`, `stat`. This is the Shortcuts route ("Open URLs"): **App Intents are not implemented**. `open?path=` only opens sets that are in the catalog. |
| Language-following sizes | File sizes follow the app language, not the system locale. |

## Data formats

| Item | Status | Note |
|---|---|---|
| `status.cache`, `scan-history.cfg`, `spotlight.snapshot`, `findertags.cfg`, `widget/widget.json` | Mac-only | New files in the data folder; upstream's files are untouched. `status.cache` (JSON) holds offline references, newest render and project-folder facts; `scan-history.cfg` the journal position per root (tab separated); `spotlight.snapshot` what was donated to Spotlight; `findertags.cfg` the Finder tags Alive added; `widget/widget.json` the widget's data (its own subfolder, the only place the widget's sandbox may read). |
| `settings.cfg`, `notes.cfg`, `home.cfg`, `previews.cfg`, `nebula.cfg`, `alive.log`, `probes.txt` | Done | Unknown keys round-trip unchanged; Mac-only keys are extra lines (`lang=`, `spotlight=`, `menubar=`, `findertags=`; `sets-columns.json` is a separate file). Each `.cfg` is written whole (temp file + rename) with the previous version kept as `<name>.bak` (also `scan-history.cfg`); an identical save writes nothing (upstream's `File.Replace` would push the real previous version out of `.bak`). A file that exists but whose bytes the system would not hand over is never overwritten (`settings.cfg`, `notes.cfg`, `home.cfg`, `previews.cfg`, `nebula.cfg`); a file that reads but is not text is copied to `<name>.orig` (`.orig2`, … — never `.bak`, which every save replaces) and starts empty; an empty file is never copied over a good `.bak`. `uiscale=` and `previewvolume=` are upstream's keys. |
| `index.cache`, `activity.cache`, `samples.cache` | Simplified | Written in the .NET `BinaryWriter` layout and tested against hand-verified bytes, but **never verified against a cache written by the real Windows app**. `activity.cache` has a `proj` tail and `samples.cache` a `walk` tail (12 bytes: the time of the last walk) behind the data upstream reads; the versions are unchanged, so a reader that stops there never sees them. A `samples.cache` without the tail (0.3.2, Windows) is dated by its modification time, like upstream. |
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
  are copied to `.orig` before anything is rewritten (UTF-16 and Windows-1252 files from the Windows app
  are read), and `alive.log` writes the home folder as `~`.

### Upstream 1.3.1–1.3.3: skipped or different

Windows-only, not ported:

- **f727588, DPI-aware layout.** AppKit scales every view with the display; nothing to do.
- **`SmoothScrollEngine` changes, `WM_MOUSEHWHEEL` / `WM_MBUTTONDBLCLK` plumbing, the GDI frame cache and `ScrollFade` internals, the `PaintSlider` / `TrackOf` refactor.** Native scrolling; the preview canvas keeps its body as a picture and draws names and ruler live, with thin scrollbars that fade out.
- **Rounded menu corners, the primary button "on glass without a grey rectangle".** Menus are native; the primary button is a gradient capsule, not a GDI bitmap.
- **Mouse wheel over a slider (steps of 5 %).** The panel scrolls instead; a focused volume slider takes ← / → by 5 %.
- **`WaveReader` try/catch for a file that is busy.** macOS has no exclusive locking of open files; the cut-short / unreadable half is covered.

Different on purpose:

- **The "Rescue Project…" menu item is Title Case** like "Show in Finder" (upstream: "Rescue project…").
- **The detail panel's footer menu shows no key hints** (inside a window SwiftUI would register them as live key equivalents next to the same ones in the menu bar); the row's context menu does.
- **The plugin Filters counter still counts only the plugins that pass the filter** (upstream did not change it either).
- **A broken `settings.cfg` shows no banner** (upstream is silent, too): edits are kept in memory, nothing is written over the file, and `alive.log` has one line.
- **Interface scale: about 300 literal `.frame` / `.padding` numbers in views are not scaled**, mostly in the player window, tiles, Stat controls, cells, Rescue and the Samples views. Everything that reads a `Theme` metric or font is.

## Owner decisions

Decided by the repository owner on 2026-11-04:

- **Notarization: set up.** The release pipeline signs with a Developer ID certificate and notarizes
  when the Apple credentials are registered as repository secrets (see `docs/RELEASING.md`); without
  them it falls back to the ad-hoc build and says so in the release.
- **Shortcuts: the `alive://` URL scheme is the supported route.** App Intents (which would need an
  Xcode host project) are not planned.
- **"Ready to open" counts keep both units, labelled.** Home counts projects (each project judged by
  its newest set, "158 / 554 projects"); the Sets toggle counts sets ("200 sets").
- **Upstream 1.3.1–1.3.3 is ported in full** (procedure in `docs/UPSTREAM.md`); the Windows-only
  parts are listed under "Deviations" below.
- **Root `README.md` stays upstream's file.** The Japanese version of it lives in `README.ja.md`; the
  Mac README is `.github/README.md` / `README.en.md`.

## Known gaps / tech debt

- **Rescue for Audio Units has never been run against Live itself.** Treat it as experimental until
  someone has confirmed that Live skips a disabled AU.
- **Caches were never checked against the Windows app** (see Data formats). A cache written by the
  Windows app may be ignored and rebuilt; that is safe but unverified.
- **Duplicated logic:** `Export/CollectScan.swift` (`CollectOrigin`, `CollectDependency`) and
  `Samples/SampleScan.swift` (`SampleOrigin`, `SampleDep`) classify a set's file references in almost
  the same way. Upstream also has two copies (`CollectAll.cs`, `SampleScan.cs`), so they were kept to
  stay diffable; merging them is safe but should be done with both slices' tests.
- No per-column search.
- VST2 plugins are matched by name only; no architecture (arm64/x86_64) check.
- Live 12's plugin database (SQLite) is not read; on Live 12 the list relies on the bundle scan.
- Releases are signed with a Developer ID and notarized when the Apple credentials are registered as repository secrets (`docs/RELEASING.md`); a release built without them is ad-hoc signed, says so in its notes, and needs System Settings → Privacy & Security → Open Anyway on macOS 15+ at first launch.
  Sparkle-style in-app updating is not implemented; the update check only opens the release page.
- The Home overview and the Stat window are drawn with Canvas; very large libraries (10,000+ sets) are
  untested.
- `tests` run without a display; the SwiftUI layouts are checked by hand (screenshots) only.
- No screenshots are committed to the README: they would show a real library.
