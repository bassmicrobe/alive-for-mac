# Alive for Mac — architecture (what wave 2 calls)

Binding rules are in `PORTING.md`. This file is the concrete API as of wave 1.5. All UI types are
internal to `AliveUI`; all models are `@MainActor @Observable`.

## Launch sequence

`AliveApp.init` → `Startup.begin()` (`Diag.start`, uncaught ObjC exception logger → `alive.log`) →
`AppModel(dataDir: AppHome.path)` loads `Settings`, sets `Localizer.shared.preference` from
`settings.lang` → `MainWindow.task` → `AppDelegate.attach(app)` + `app.start()` →
`CatalogModel.start()`: cache loaded off the main thread and published, then a background scan if
there is an enabled root. Finder-opened `.als` paths queue in `app.pendingOpenPaths` until the
catalog is ready (`OpenPathPlan`).

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
new list must expose `shownCount`.

Tests: `AppModel(dataDir: scratch)`; never call `AppModel()` in tests (see `makeModel()` in
`AppModelTests.swift`).

## CatalogModel (`Catalog/CatalogModel.swift`)

Published: `sets: [SetEntry]` (all), `projects` (folded per folder when `settings.groupByFolder`),
`env: LiveEnvironment`, `history: Activity`, `isScanning`, `progress: CatalogProgress`
(`done,total,current,fraction?`), `lastScanStats`, `isLoaded`, `isReady` (= loaded and not scanning),
`revision` (bumped on each publish; memoize on it), `hasEnabledRoots`.
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
