# Alive for Mac — porting plan

This is the contract every implementer follows. Read it fully before writing code.

Alive (upstream: <https://github.com/rueblose/alive>, C# WinForms, Windows-only) is a catalog for
Ableton Live projects, plugins and samples. This repository is a fork of it. **Alive for Mac** is a
native Swift rewrite of it for macOS that lives in `macos/`, next to the untouched upstream sources.

## 1. Goals and non-goals

- Native macOS app (SwiftUI + AppKit where SwiftUI falls short), macOS 14+, Apple Silicon and Intel.
- Feature parity with upstream as far as the platform allows. Anything simplified or skipped is
  listed honestly in `macos/PARITY.md`.
- UI in **English and Japanese**, switchable in the app at runtime (System / English / 日本語).
- Upstream updates stay easy to take in: see §3.
- No Windows build. Upstream's C# stays in the repo only as the porting reference.

## 2. Ground rules (hard)

1. **Never edit upstream-owned files** (`src/`, `nebula/`, `tools/`, `docs/`, `README*.md`,
   `FORMAT.md`, `LICENSE`, `build.cmd`, root `.gitignore`, `.gitattributes`). Everything new goes
   in `macos/` or `.github/`. This keeps `git merge upstream/main` conflict-free.
2. **License.** Root `LICENSE` is upstream's MIT notice and stays byte-for-byte. It is copied
   verbatim into the app bundle. The port's notice is `macos/LICENSE` + `macos/NOTICE.md`. The app
   shows credits (original author + link), both licenses and the trademark note in Settings → About.
   Never write "Alive by <someone>" in a way that implies upstream endorses this port.
3. **No third-party dependencies.** Apple frameworks and system zlib only.
4. **No App Sandbox.** The app reads `~/Library/Preferences/Ableton/…`, external volumes, and
   launches Live.
5. Swift 5 language mode (`swift-tools-version:5.10`), deployment target macOS 14. Use
   `@Observable` (Observation), `@MainActor` for UI models, structured concurrency for background
   work. Don't fight the compiler with `nonisolated(unsafe)` sprinkles; keep background work in
   plain functions that take and return value types.
6. `AliveCore` = pure logic: Foundation + CZlib only. **No SwiftUI/AppKit imports, no
   user-visible strings** (return enums / typed errors; the UI localizes them). Log text is English.
7. **Keep upstream's data-file formats and names** (`settings.cfg`, `index.cache`, `notes.cfg`,
   `home.cfg`, `previews.cfg`, `samples.cache`, `activity.cache`, `nebula.cfg`, `thumbs/`,
   `alive.log`, `probes.txt`). Mac-only settings are extra keys in `settings.cfg`; unknown keys must
   round-trip unchanged.
8. **Port, don't reinvent.** Keep upstream type names (`SetEntry`, `ProjectIndex`, `SampleIndex`…)
   and member names in Swift casing, so a future upstream diff maps onto the Swift file directly.
   Each Swift file starts with `// Port of src/Foo.cs` (or `// Mac-only: …`). Keep the *why*
   comments that matter (condensed, English); drop WinForms plumbing.
9. Files ≤ 800 lines (aim 200–400), functions small, early returns, no force-unwraps on external
   data, never silently swallow errors that the user should know about (log them via `Diag`).
10. Read `FORMAT.md` before touching anything under `Als/`. It documents traps such as
    `MasterTrack` vs `MainTrack` and the empty `<Name>` nested in `Vst3PluginInfo`.

## 3. Taking in upstream updates

Because the port is a rewrite, "taking in" an upstream update means a **tracked porting step**,
not an automatic code merge:

1. `macos/scripts/upstream-sync.sh` fetches `upstream` (rueblose/alive), merges `upstream/main`
   into the current branch (conflict-free thanks to rule 2.1), and prints every upstream commit
   since `macos/UPSTREAM_SYNC` with the C# files it touched, each mapped through
   `macos/upstream-map.tsv` to the Swift file(s) that must be updated.
2. A developer (or Claude Code) ports those changes, runs the tests, and runs
   `upstream-sync.sh --mark` which writes the new upstream SHA into `macos/UPSTREAM_SYNC`.
3. `.github/workflows/upstream-watch.yml` runs weekly and opens/updates a GitHub issue listing
   unported upstream commits, so nothing is missed.

When you add or rename a Swift file that ports an upstream file, update `upstream-map.tsv` in your
final report (the orchestrator edits the file; don't edit it yourself in parallel waves).

## 4. Layout

```
.github/README.md, README.ja.md        Mac README (GitHub shows .github/README.md first)
.github/workflows/macos-ci.yml         build + test on macOS runner
.github/workflows/upstream-watch.yml   weekly upstream report issue
macos/
  Package.swift  LICENSE  NOTICE.md  PARITY.md  UPSTREAM_SYNC  upstream-map.tsv
  docs/PORTING.md (this file)  docs/UPSTREAM.md (how to port an update)
  scripts/build-app.sh  scripts/upstream-sync.sh
  Sources/CZlib/                       system zlib module
  Sources/AliveCore/{Infra,Als,Live,Catalog,Plugins,Samples,Rescue,Export,Update}/
  Sources/AliveUI/{App,L10n,Theme,Services,Catalog,Home,Sets,Plugins,Samples,Stat,Rescue,Export,Settings,Help}/
  Sources/AliveForMac/main.swift       `AliveApp.main()`
  Tests/AliveCoreTests/  Tests/AliveUITests/
```

## 5. Windows → macOS mapping

| Upstream (Windows) | Alive for Mac |
|---|---|
| `%APPDATA%\Alive` | `~/Library/Application Support/Alive for Mac/` (override: `ALIVE_HOME`) |
| `%APPDATA%\Ableton\Live x\Preferences\` | `~/Library/Preferences/Ableton/Live x/` (Library.cfg, Log.txt, PluginScanDb.txt if present, Crash/) |
| `C:\ProgramData\Ableton\Live x\Resources\` | `/Applications/Ableton Live*.app/Contents/App-Resources/` (`Core Library`, `Builtin`) |
| Documents\Ableton\User Library | `~/Music/Ableton/User Library` (or Library.cfg `ProjectPath`+`ProjectName`) |
| Registry `.als` association | `NSWorkspace.urlForApplication(withBundleIdentifier: "com.ableton.live")` / `urlForApplication(toOpen:)`; several Live versions may be installed — prefer the newest |
| Process.Start(set) | `NSWorkspace.shared.open([url], withApplicationAt: live, configuration:)` |
| Explorer /select | `NSWorkspace.shared.activateFileViewerSelecting([url])` |
| VST2 `.dll` / VST3 `.vst3` | AU `.component`, VST `.vst`, VST3 `.vst3` bundles in `/Library/Audio/Plug-Ins/{Components,VST,VST3}` and `~/Library/Audio/Plug-Ins/…`; read `Contents/Info.plist` (`AudioComponents[]`: name "Vendor: Plugin", manufacturer, type, subtype) and `Contents/Resources/moduleinfo.json` for VST3 |
| `.als` `AuPluginInfo` | children `Name`, `Manufacturer`, `ComponentType`, `ComponentSubType`, `ComponentManufacturer` (32-bit ints = FourCC). Uid form: `au:<type>:<subtype>:<manufacturer>` as FourCC text |
| FileRef paths `C:\…` | `<Path Value="/Users/…"/>` + `<RelativePath Value="../…"/>` + `RelativePathType`. Paths are POSIX; still accept backslashes from sets made on Windows |
| Media Foundation / waveOut | AVFoundation (`AVAudioPlayer`, `AVAudioFile` for waveforms) |
| FileSystemWatcher | FSEvents (`FSEventStreamCreate`) |
| Acrylic "glass" | `NSVisualEffectView` behind content, off by default |
| Smooth-scroll engine, single-instance pipe, Win32 interop | not needed (native) |
| `.zip` via System.IO.Compression | `/usr/bin/ditto -c -k --sequesterRsrc --keepParent` |
| Update check against upstream releases | GitHub API `repos/bassmicrobe/alive-for-mac/releases/latest` (never upstream's: those are Windows builds) |

Live preference folder names include betas (`Live 12.0b20`, `Live 11.3.20b1`). Version sorting must
handle them (release > beta of the same number).

## 6. Localization (EN / JA, switchable at runtime)

- `AliveUI/L10n/Localizer.swift`: `@Observable final class Localizer` with
  `static let shared`, `var preference: LanguagePreference` (`.system/.en/.ja`),
  computed `lang: Lang` (`.en/.ja`) and `locale: Locale` for number/date formatting.
  Changing it re-renders every view immediately (views read `Localizer.shared` during `body`).
  It also writes `AppleLanguages` for the app domain so system-provided UI (open panels, the app
  menu's standard items) follows after a relaunch. The choice is persisted in `settings.cfg` as
  `lang=system|en|ja`.
- `AliveUI/L10n/LocalizedStrings.swift`:
  ```swift
  public protocol LocalizedStrings: CaseIterable {
      var en: String { get }
      var ja: String { get }
  }
  extension LocalizedStrings {
      var s: String                         // current language
      func f(_ args: CVarArg...) -> String  // String(format:locale:arguments:)
  }
  ```
- **One table per feature**, each an `enum XxxStrings: LocalizedStrings` with exhaustive `switch`
  for `en` and `ja` (the compiler then guarantees every key has both translations):
  `CommonStrings` (shell, menus, toolbar, shared words), `HomeStrings`, `SetsStrings`,
  `PluginsStrings`, `SamplesStrings`, `StatStrings`, `RescueStrings`, `ExportStrings`,
  `SettingsStrings`, `HelpStrings`. Never put a user-visible literal in a view.
- Format strings use positional specifiers when order may differ (`%1$@`, `%2$lld`).
- Each table gets a test in `Tests/AliveUITests/<Feature>StringsTests.swift` calling the shared
  helper `assertStringTableIsComplete(XxxStrings.self)` (non-empty, same format specifiers in en/ja).
- Japanese style: concise UI Japanese, です/ます only in explanatory sentences, no trailing 。 on
  buttons/labels. Keep Ableton's own Japanese terms.

| English | 日本語 |
|---|---|
| Home / Sets / Plugins / Samples / Stat | ホーム / セット / プラグイン / サンプル / 統計 |
| Set, Live Set / Project | セット, Live セット / プロジェクト |
| Tempo / Key / Tracks / Live version | テンポ / キー / トラック / Live バージョン |
| Filters / Search / Scan / Rescan | フィルター / 検索 / スキャン / 再スキャン |
| Tags / Notes / Pin | タグ / メモ / ピン留め |
| Missing files / Missing plugins | 見つからないファイル / 見つからないプラグイン |
| Render / Preview / Player | レンダー / プレビュー / プレーヤー |
| Rescue | レスキュー |
| Export (Collect All and Save) | エクスポート（すべてを収集して保存） |
| Never used / Most used / Duplicates | 未使用 / よく使う / 重複 |
| Open in Live / Show in Finder | Live で開く / Finder に表示 |
| Settings / Check for updates / Data folder | 設定 / アップデートを確認 / データフォルダ |
| Installed / Not installed | インストール済み / 未インストール |
| Vendor | メーカー |

## 7. UI direction

Match upstream's look (see `docs/img/*.png`): a dark, quiet catalog — near-black background
(`#1B1B1D`), raised surfaces (`#28282A`), pill-shaped segmented tabs, rounded cards, small tag
pills, white-on-dark selection pill, generous row height, Live clip colours as the only saturated
colour. Exact tokens are in upstream `src/Theme.cs` → port them into `AliveUI/Theme/Theme.swift`
(colours, radii, paddings, font sizes). Typeface: the system font (SF Pro), the Mac counterpart of
upstream's Segoe UI. The app forces dark appearance, like upstream. Every interactive element has
designed hover / pressed / focus states. Native where it helps: toolbar, `.searchable`, `Table`,
`Settings` scene, sheets, context menus, drag and drop, Quick-Look-style preview.

Main window: single `Window` scene (no tabbing). Toolbar: tab pills (Home/Sets/Plugins/Samples),
Filters button, search field, "N shown" counter; trailing icons Stat, Scan folders, Settings, Help.
Sets/Samples show an inspector panel on the right (upstream `DetailPanel`).

### Keyboard shortcuts (Mac mapping)

| Action | Upstream | Mac |
|---|---|---|
| Home / Sets / Plugins / Samples | Ctrl 1…4 | ⌘1…⌘4 |
| Stat window | toolbar | ⌘5 |
| Search | Ctrl F | ⌘F |
| Filters | F | ⌥⌘F |
| Scan folders… | Shift F | ⇧⌘O |
| Rescan | F5 | ⌘R |
| Open set in Live | Enter | ⌘O, Return / double-click in a list |
| Show in Finder | Shift Enter | ⇧⌘R |
| Play / pause render or sample | Space | Space in a focused list (`onKeyPress`), menu ⌥⌘P |
| Arrangement preview | Ctrl Space | ⌘Y |
| Pin set | Q | ⌘D |
| Tags and notes | Ctrl T | ⌘T |
| Rescue a set | Ctrl R | ⌥⌘R |
| Export (collect all) | panel button | ⌘E |
| Launch Live / new set | Ctrl N | ⌘N |
| Settings | Ctrl , | ⌘, |
| Help | F1 | ⌘? |
| Fullscreen / minimize / quit | F11 / Ctrl M / Ctrl Q | ⌃⌘F / ⌘M / ⌘Q |

## 8. Architecture

- `AppModel` (`@MainActor @Observable`, one per app, `AliveUI/App/AppModel.swift`): settings,
  current tab, search text, presentation state (`sheet: AppSheet?`), and one feature model per
  feature: `catalog: CatalogModel`, `home: HomeModel`, `sets: SetsModel`, `plugins: PluginsModel`,
  `samples: SamplesModel`, `stat: StatModel`, `player: PlayerModel`, `rescue: RescueModel`,
  `export: ExportModel`. Each feature model lives in its feature folder, takes `unowned let app`,
  and is owned by exactly one implementer.
- `CatalogModel` wraps `ProjectIndex`: loads the cache instantly at launch, rescans in the
  background with progress, publishes `sets: [SetEntry]`, grouped projects, and the `LiveEnvironment`.
- `AppSheet` enum (in `App/SheetHost.swift`) lists every sheet with plain payloads (paths as
  `String`); `SheetHost` switches to the owning feature's view.
- Extra windows: `Settings` scene, `Window(id: "stat")`, `Window(id: "player")`.
- `Services/`: `AudioPlayback` (AVAudioPlayer wrapper, `@Observable`: url, isPlaying, time,
  duration, volume, play/pause/stop/seek) used by the player *and* sample audition;
  `LiveLauncher` (find Live apps, open a set in Live, launch Live); `Finder` (reveal, open folder).
- Background work: `Task.detached` / task groups with bounded concurrency
  (`ProcessInfo.activeProcessorCount`), results handed back to `@MainActor` models. Cancellation on
  rescan. Never block the main thread on disk.
- Errors: core throws typed errors; UI shows a `Toast` or an inline message, and `Diag` logs details
  to `alive.log`.

## 9. Work breakdown and file ownership

Parallel implementers work in separate git worktrees. **Only edit files you own.** If you truly need
a change in a shared file (`AppModel.swift`, `AppCommands.swift`, `MainWindow.swift`,
`SheetHost.swift`, `Theme.swift`, `Components.swift`), keep it minimal and additive, and list it in
your final report. Placeholders created by the shell agent for your feature are yours to replace.

**Wave 1 (parallel)**
- **1A shell** — `AliveUI/App/*`, `AliveUI/L10n/*` + `CommonStrings`, `AliveUI/Theme/*`,
  `AliveUI/Services/*`, `AliveUI/Settings/*` (language switch, transparency toggle, data folder,
  About/credits/licenses), `AliveUI/Help/*`, placeholder files (views + feature models with stub
  methods used by the menus) for every other feature folder, `Tests/AliveUITests/*` helper,
  `scripts/build-app.sh`.
- **1B core spine** — `AliveCore/Infra/{AppHome,Diag,Settings}.swift`, `Als/{Gzip,AlsFile,Arrangement,ArrangementLoader,Scales,LiveColors,RefResolver}.swift`,
  `Live/LiveEnvironment.swift`, `Catalog/{FolderScan,ProjectIndex,Activity,RenderIndex,ProjectMeta,HomeStore}.swift`,
  `Plugins/PluginInventory.swift` (**minimal stub** with the upstream API ProjectIndex needs —
  S3 completes it), `Tests/AliveCoreTests/*`.
- **1C repo infra** — `scripts/upstream-sync.sh`, `docs/UPSTREAM.md`,
  `.github/workflows/{macos-ci,upstream-watch}.yml`.

**Wave 1.5 (single)** — integrate 1A+1B: `CatalogModel`, settings/localizer persistence, launch
scan, a working minimal Sets list, end-to-end run against a real library.

**Wave 2 (parallel vertical slices, core + UI + strings + tests)**
- **S1 Sets** — `Catalog/{FolderWatch,SetFilter}.swift`; `AliveUI/Sets/*` (SetsView table with
  configurable columns, version folding, sort, search, pin; OverviewPanel; DetailPanel inspector;
  FiltersSheet; TagsSheet (tags+notes); RootsSheet (project and sample roots)).
- **S2 Home / preview / player** — `AliveUI/Home/*` (HomeView tiles + year of activity,
  ArrangementRender, ThumbCache, PreviewSheet, PlayerWindow + PlayerModel, MediaKeys).
- **S3 Plugins** — `Plugins/{PluginInventory,PluginFilter}.swift`; `AliveUI/Plugins/*`.
- **S4 Samples** — `AliveCore/Samples/*`; `AliveUI/Samples/*`.
- **S5 Stat + updates** — `AliveUI/Stat/*`; `Update/UpdateCheck.swift`; update section of Settings.
- **S6 Rescue + Export** — `Live/LiveLog.swift`, `AliveCore/Rescue/*`, `AliveCore/Export/*`;
  `AliveUI/Rescue/*`, `AliveUI/Export/*`.

**Wave 3** — merge, integration fixes, review, `PARITY.md`, READMEs.

## 10. Testing

- XCTest. Core logic targets ≥ 80 % line coverage where feasible.
- Fixtures are generated in code: build XML strings, gzip them with `Gzip.compress`, write to a temp
  dir. Never commit user data and never hardcode paths from this machine.
- Real-library smoke tests are gated by env vars and skipped otherwise:
  `ALIVE_TEST_SETS=/path/to/projects` (parse every set, no crash, sane stats),
  `ALIVE_TEST_SAMPLES=/path/to/samples`. The parser differential (reference XMLParser vs tokenizer) is heavier and has its own gate, `ALIVE_TEST_PARSER_DIFF`. `swift test --filter` does not select tests with this toolchain; run the whole suite with the env var set.
- Every string table has its completeness test.
- Before reporting done: `swift build` and `swift test` are green in `macos/`, with no new warnings
  in your files.

## 11. Definition of done (per implementer)

1. Your files compile, tests pass, no placeholder left in your area, no `TODO` without an issue note.
2. Every user-visible string localized (en + ja).
3. Commit on your branch with conventional commits (`feat(mac): …`). No attribution trailers.
4. Final report: what you built, what you simplified or skipped vs upstream (for `PARITY.md`),
   shared files you touched, new/renamed files for `upstream-map.tsv`, how you verified it.
