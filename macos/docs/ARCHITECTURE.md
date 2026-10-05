# Alive for Mac — architecture (developer map)

Binding rules are in `PORTING.md`; what differs from upstream is in `../PARITY.md`. This file is the
concrete map of the finished port: modules, launch sequence, the models and how to extend them. All
UI types are internal to `AliveUI`; all models are `@MainActor @Observable`.

## Modules

| Target | Contents | Rules |
|---|---|---|
| `CZlib` | system zlib module map | |
| `AliveCore` | pure logic, Foundation + CZlib only, no user-visible strings. `Infra` (AppHome, Diag, Settings, Parallel, `FileStat`), `Als` (gzip, tokenizer, arrangement, refs), `Catalog` (scan, ProjectIndex, caches, FolderWatch, SetFilter, ProjectMeta, HomeStore), `Live` (environment, log, versions), `Plugins` (bundle scanner, inventory, filter, table), `Samples` (walk, index, usage, copies, cache), `Rescue` (probe, session, patching), `Export` (collect plan/scan/copy), `Update` (release check, schedule) | log text English; typed errors |
| `AliveUI` | SwiftUI/AppKit: `App` (AliveApp, AppModel, MainWindow, AppCommands, SheetHost, DebugLaunch), `L10n`, `Theme`, `Services`, and one folder per feature (`Catalog`, `Home`, `Sets`, `Plugins`, `Samples`, `Stat`, `Rescue`, `Export`, `Settings`, `Help`) | every string in an `XxxStrings` table (en + ja) |
| `AliveForMac` | `main.swift` calling `AliveApp.main()` | |

Tests: `Tests/AliveCoreTests` (parsers, caches, scanners, rescue, export...) and `Tests/AliveUITests`
(models, string tables, pure formatting). Fixtures are built in code; real-library smoke tests are gated
by `ALIVE_TEST_SETS`, `ALIVE_TEST_SAMPLES`, `ALIVE_TEST_PARSER_DIFF`.

## Launch sequence

`AliveApp.init` → `Startup.begin()` (`Diag.start`, uncaught ObjC exception logger → `alive.log`) →
`AppModel(dataDir: AppHome.path)` loads `Settings`, sets `Localizer.shared.preference` from
`settings.lang` → `MainWindow.task` → `AppDelegate.attach(app)` + `app.start()`:
1. `RescueProbe.cleanupStale(dir:)` removes leftover probe copies listed in `probes.txt`.
2. `CatalogModel.start()`: cache loaded off the main thread and published, then a background scan if
   there is an enabled root; it also starts `app.sets.watcher` (FSEvents, new sets appear by themselves).
3. `SamplesModel.start()`: `samples.cache` shown at once, then a quiet background walk.
4. When the catalog is ready: `catalogDidBecomeReady()` flushes Finder-opened paths
   (`app.pendingOpenPaths`, `OpenPathPlan`) and calls `UpdateModel.shared.dailyCheckIfDue` (a no-op
   unless the daily check is on).
5. `DebugLaunch.apply` (only when `ALIVE_DEBUG_*` variables are set).

## AppModel (`App/AppModel.swift`)

State: `tab: MainTab`, `searchText`, `selectedSetPath: String?`, `sheet: AppSheet?`, `toasts`,
`settings: AppSettings` (read-only outside; `AppSettings` = core `Settings`, alias because SwiftUI has a
`Settings` scene), `dataDir`, `prefs: AppPreferences`, `audio: AudioPlayback`.
Feature models (each owned by one implementer, `unowned let app`): `catalog`, `home`, `sets`, `plugins`,
`samples`, `stat`, `player`, `rescue`, `export`.

Actions: `mutateSettings { $0.x = … }` (applies, saves `settings.cfg` atomically only when changed, logs
and toasts a failed write; **the only way to change settings**), `toast(_:kind:)`, `openInLive(path:)`,
`launchLive()`, `revealInFinder(path:)`, `rescan()`, `openPaths(_:)`, `present*()` (sheets),
`selectedSetPath` helpers (`openSelectedInLive`…). `shownCount` comes from the active tab's model, so a
new list must expose `shownCount`; `shownLabel` overrides the counter text (Samples: "12,923 samples ·
23.7 GB") and `activeFilterCount` feeds the badge on the Filters pill. ⇧⌘R reveals the selected set, or
the selected plugin on the Plugins tab. `mutateSettings` also re-syncs the sample roots when they change.

Tests: `AppModel(dataDir: scratch)`; never call `AppModel()` in tests (see `makeModel()` in
`AppModelTests.swift`).

## CatalogModel (`Catalog/CatalogModel.swift`)

Published: `sets: [SetEntry]` (all), `projects` (folded per folder when `settings.groupByFolder`),
`env: LiveEnvironment`, `history: Activity`, `isScanning`, `progress: CatalogProgress`
(`done,total,current,fraction?`), `lastScanStats`, `isLoaded`, `isReady` (= loaded and not scanning),
`revision` (bumped on each publish; memoize on it), `hasEnabledRoots`.
`lastScanStats.failedRoots` / `unreadableFolders` expose access failures. If an enabled root is
unreadable, the previous catalog and disk caches are retained (`retainedPreviousCatalog`); Home
and Sets show recovery actions and a persistent notice when older rows remain visible. New
partial updates wait for a complete scan, while a readable empty root still clears deleted rows.
Actions: `rescan()` (cancels and restarts; a no-op before `start()`, so root edits in tests never scan), `addRoots([String])` / `addRoot(_)` (a file counts as its
folder; toasts; saves; rescans), `removeRoot(_)`, `setRoot(_:enabled:)`, `settingsDidChange()`.
`index: ProjectIndex` is exposed for what the model does not wrap (`inSameFolder`, `inventory`,
`usage`…); read it, don't scan through it. Filter *then* fold: use `SetSearch.rows(_:query:groupByFolder:)`
or `ProjectIndex.collapseByFolder` after your own filter.

`SetsModel.rows` = catalog narrowed by `app.searchText` (memoized), `shownCount = rows.count`.

## Preferences

`app.prefs.language | transparency | dailyUpdateCheck | pluginSource` are computed views onto `settings`
(`lang`, `!disableGlass`, `checkUpdates`, `pluginsFromFolders`); setters write through `mutateSettings`.
Changing `pluginSource` rescans. No UserDefaults except Localizer's `AppleLanguages` write.

## Services (`Services/`)

- `AudioPlayback` — **one instance, `app.audio`**: `play(url:) -> Bool`, `pause()`, `resume()`,
  `togglePlayPause()`, `stop()`, `seek(to:)`, `volume`, observable `url/isPlaying/currentTime/duration`,
  `onFinished`. `onError` is wired to a toast by `AppModel`; don't create another instance (sounds must
  not overlap). `PlayerModel.audio` and `SamplesModel.audio` forward to it.
- `LiveLauncher` (`@MainActor` enum) — `installedApps()`, `newest()`, `open(setAt:)`, `launch()`;
  versions are core `LiveVersion`. Errors: `LiveLauncherError`. Go through `app.openInLive/launchLive`
  to get the localized toast.
- `Finder` — `reveal(path:)`, `openFolder(path:)`; go through `app.revealInFinder`.
- `FolderPicker.chooseFolders(message:prompt:) -> [String]` — NSOpenPanel for directories.

## Shared UI

`Theme` (tokens: colours, radii, sizes, fonts, animations), `Components.swift`: `PillButton(title:icon:kind:)`,
`PillTabs`, `CircleIconButton`, `TagPill`, `SurfaceCard`, `SectionHeader`, `EmptyState`, `SheetFrame`,
`.rowHover()`, `.focusRing(_:cornerRadius:)`; `IconView(icon: AppIcon)`; `ToastOverlay`.
`RootsEmptyState` (first-run screen; Home and Sets show it while `!catalog.hasEnabledRoots` — keep that
when replacing `HomeView`/`SetsView`). `SetFormat` (cell text), `SetSearch`, `RootSuggestions`,
`OpenPathPlan` are pure and tested.

## L10n

`enum XxxStrings: LocalizedStrings` with `en` and `ja`; use `XxxStrings.case.s` or `.f(args…)`.
Shared words live in `CommonStrings`. Add a `Tests/AliveUITests/XxxStringsTests.swift` calling
`assertStringTableIsComplete`.

## Adding a sheet / menu item

Sheet: add a case to `AppSheet` (+ its `id`) and to `SheetHost`, add `app.presentXxx()` in `AppModel`,
present with `.sheet(item: $app.sheet)` (already in `MainWindow`); use `SheetFrame` for chrome.
Menu item: add a `Button` with `.keyboardShortcut` in `AppCommands`, calling an `AppModel` action;
add its title to `CommonStrings` and the shortcut to the Help sheet table.
Settings key: add the field to core `Settings` (load/serialize), expose it in `AppPreferences`.

## Feature models (owned by their folder; `unowned let app`)

| Model | Folder | What it is |
|---|---|---|
| `HomeModel`, `PlayerModel` | `Home/` | tiles, pins, overview/heatmap, thumbnails (`ThumbCache`, `ThumbnailPipeline`), arrangement render and preview sheet, the player window, `MediaKeys` (MPRemoteCommandCenter) |
| `SetsModel` | `Sets/` | filter + sort + fold pipeline (`SetsPipeline`), `Table` with saved columns (`SetsColumnStore`, `sets-columns.json`), inspector (`DetailPanel`), tags (`app.sets.meta` is the shared `ProjectMeta`; observe `metaRevision`), roots sheet, `CatalogWatcher` |
| `PluginsModel` | `Plugins/` | `PluginInventory` rows, summary cards, filters, list, `show(pluginNamed:)`, `reveal(_:)` |
| `SamplesModel` | `Samples/` | index (`SampleIndex`), tree/flat listing, lenses, audition (`+Audition`), scan (`+Scan`), panel; `showFolder(_:)` is the entry point from the Sets inspector |
| `StatModel` | `Stat/` | point cloud scene, camera, mapping channels, palette, inspector |
| `RescueModel`, `ExportModel` | `Rescue/`, `Export/` | the two sheets on top of `RescueSession` / `CollectAll` |
| `UpdateModel.shared` | `Settings/` | manual and daily update check, `hasUnseenUpdate` (dot on the Settings gear) |

Cross-feature calls go through these entry points, not through views: `app.sets.select(path:)`,
`app.plugins.show(pluginNamed:)`, `app.samples.showFolder(_:)`, `app.home.togglePin(path:)`.

## Things that bite

- **Home grid keys belong to focused tiles** (`HomeGridKeyboard`), not a window-wide event monitor.
  Keep toolbar buttons, search, and player controls free to process their own keys.
- **Thumbnail cache costs must survive cache hits.** Both NSCaches have independent 64 MiB
  budgets; a replacement wrapper without its decoded image cost defeats eviction.
- **Large previews reduce resolution below 1x to honor the pixel budget.** At that scale,
  `ArrangementRender` downsamples logical geometry uniformly; rounding each track separately
  would crop the final tracks.
- **Sample row lookup is local to its containing folder.** Folder operations must not build
  full paths for every sample. Case-only folder names still share the case-insensitive lookup.

- **Table cells must not read `@Environment(AppModel.self)`.** When the rows shrink, NSTableView keeps
  cells alive outside the environment and SwiftUI aborts with "No Observable object of type AppModel
  found". Pass `app` as a plain `let` (see `Sets/SetsCells.swift`).
- **Use `FileStat.of(path)` (stat(2)), not `FileManager.attributesOfItem`,** in anything that runs per file:
  the latter also reads extended attributes, which is ~28 ms per file on an SMB volume.
- **Don't raise the top bar's minimum widths.** The bar must fit in 1120 pt in Japanese with the scan
  pill showing; the search field shrinks (min 80) instead.
- Missing plugins are a *state* (PORTING rule 11): one aggregated mark per set, one notice per screen.

## Automated screenshots (no clicks)

Launch the built app in the background with `ALIVE_NO_ACTIVATE=1` and a scratch `ALIVE_HOME`; the
window numbers are written to `alive.log` (`window-number: …`), so `screencapture -l <n> -o file.png`
photographs just our window. `ALIVE_DEBUG_TAB`, `ALIVE_DEBUG_SELECT`, `ALIVE_DEBUG_PLUGIN`,
`ALIVE_DEBUG_SHEET`, `ALIVE_DEBUG_WINDOW` (`stat|player|settings`) and `ALIVE_DEBUG_SETTINGS_TAB=about`
put the app in the state you want (list at the top of `App/DebugLaunch.swift`). Pass
`-ApplePersistenceIgnoreState YES` so a previously killed run does not show the "reopen windows?"
dialog, and delete stale `NSWindow Frame …` defaults if the window opens at the wrong size.
