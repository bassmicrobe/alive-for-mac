// Mac-only: the one app-wide model (docs/PORTING.md §8). Owns presentation state and one feature
// model per feature; contextual actions used by menus and toolbar live here.
import Foundation
import Observation
import AliveCore

enum MainTab: String, CaseIterable, Identifiable {
    case home, sets, plugins, samples

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return CommonStrings.tabHome.s
        case .sets: return CommonStrings.tabSets.s
        case .plugins: return CommonStrings.tabPlugins.s
        case .samples: return CommonStrings.tabSamples.s
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var tab: MainTab = .home
    var searchText = ""
    /// The set currently selected in any view (path of the .als).
    var selectedSetPath: String?
    var sheet: AppSheet?
    var toasts: [ToastMessage] = []
    /// Bumped by ⌘F; the toolbar's search field focuses itself when it changes.
    var searchFocusRequest = 0
    /// Files handed to the app by Finder ("Open With", `open -a`) that wait for the catalog.
    private(set) var pendingOpenPaths: [String] = []
    /// Paths whose folder was just added as a root: select them once that scan is done.
    @ObservationIgnored private var reselectPaths: [String] = []

    /// The core settings (settings.cfg). Change them only through `mutateSettings`.
    private(set) var settings: AppSettings
    /// Where settings.cfg and the caches live (`AppHome.path`; tests pass a scratch folder).
    @ObservationIgnored let dataDir: String
    /// The one audio player of the app: render playback and sample audition share it, so two
    /// sounds never overlap. Its errors surface as toasts.
    @ObservationIgnored let audio = AudioPlayback()
    @ObservationIgnored private var started = false

    @ObservationIgnored lazy var prefs = AppPreferences(app: self)

    // Feature models. `lazy` because each takes `self`; ignored by Observation because the
    // references never change (their own properties are observed).
    @ObservationIgnored lazy var catalog = CatalogModel(app: self)
    @ObservationIgnored lazy var home = HomeModel(app: self)
    @ObservationIgnored lazy var sets = SetsModel(app: self)
    @ObservationIgnored lazy var plugins = PluginsModel(app: self)
    @ObservationIgnored lazy var samples = SamplesModel(app: self)
    @ObservationIgnored lazy var stat = StatModel(app: self)
    @ObservationIgnored lazy var player = PlayerModel(app: self)
    @ObservationIgnored lazy var rescue = RescueModel(app: self)
    @ObservationIgnored lazy var export = ExportModel(app: self)

    init(dataDir: String = AppHome.path) {
        self.dataDir = dataDir
        settings = AppSettings.load(dir: dataDir)
        Localizer.shared.preference = LanguagePreference(configValue: settings.lang)
        audio.onError = { [weak self] error in
            MainActor.assumeIsolated {
                self?.toast(CommonStrings.audioFailed.f(error.localizedDescription), kind: .error)
            }
        }
    }

    /// Called once by the main window: starts the catalog (cache, then scan).
    func start() {
        guard !started else { return }
        started = true
        RescueProbe.cleanupStale(dir: dataDir)
        catalog.start()
        samples.expandsRootsOnFirstLoad = true
        samples.start()
    }

    // MARK: - Settings

    /// Applies `change` to the settings and writes settings.cfg atomically when something changed.
    /// A failed write is logged and shown; the in-memory value stays.
    func mutateSettings(_ change: (inout AppSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        let groupingChanged = next.groupByFolder != settings.groupByFolder
        let sampleRootsChanged = next.sampleRoots != settings.sampleRoots
            || next.disabledSampleRoots != settings.disabledSampleRoots
        settings = next
        saveSettings()
        if groupingChanged { catalog.settingsDidChange() }
        if sampleRootsChanged { samples.syncRoots() }
    }

    func saveSettings() {
        do {
            try settings.save(dir: dataDir)
        } catch {
            Diag.fail("save settings.cfg", error)
            toast(CommonStrings.settingsSaveFailed.f(error.localizedDescription), kind: .error)
        }
    }

    // MARK: - Toolbar state

    var shownCount: Int {
        switch tab {
        case .home: return home.shownCount
        case .sets: return sets.shownCount
        case .plugins: return plugins.shownCount
        case .samples: return samples.shownCount
        }
    }

    /// Overrides "N shown" in the toolbar (Samples: "12,923 samples · 23.7 GB"); nil: the plain count.
    var shownLabel: String? { tab == .samples ? samples.shownLabel : nil }

    /// Number of filters that are on for the tab (badge on the Filters pill).
    var activeFilterCount: Int {
        switch tab {
        case .sets: return sets.activeFilterCount
        case .plugins: return plugins.filter.activeCount
        case .home, .samples: return 0
        }
    }

    var hasSelectedSet: Bool { selectedSetPath != nil }

    var canPresentFilters: Bool { tab == .sets || tab == .plugins }

    // MARK: - Toasts

    func toast(_ text: String, kind: ToastMessage.Kind = .info) {
        let message = ToastMessage(text: text, kind: kind)
        toasts.append(message)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(kind == .error ? 4 : 2.5))
            self?.toasts.removeAll { $0.id == message.id }
        }
    }

    // MARK: - Contextual actions

    /// Files from Finder / `open -a`. They wait until the catalog is ready, then `flushPendingOpen`
    /// selects each known set (Sets tab) or takes its folder in as a new root (upstream OpenPaths).
    func openPaths(_ paths: [String]) {
        pendingOpenPaths.append(contentsOf: paths)
        flushPendingOpen()
    }

    /// Called by `CatalogModel` whenever it becomes ready (cache loaded with no roots, or a scan ended).
    func catalogDidBecomeReady() {
        if !reselectPaths.isEmpty {
            let paths = reselectPaths
            reselectPaths = []
            select(OpenPathPlan.make(paths: paths, sets: catalog.sets, roots: settings.roots,
                                     disabledRoots: settings.disabledRoots).select)
        }
        flushPendingOpen()
        UpdateModel.shared.dailyCheckIfDue(app: self)
    }

    func flushPendingOpen() {
        guard catalog.isReady, !pendingOpenPaths.isEmpty else { return }
        let paths = takePendingOpenPaths()
        let plan = OpenPathPlan.make(paths: paths, sets: catalog.sets, roots: settings.roots,
                                     disabledRoots: settings.disabledRoots)
        select(plan.select)
        plan.openDirectly.forEach { openInLive(path: $0) }
        guard !plan.addRoots.isEmpty else { return }
        if !catalog.addRoots(plan.addRoots).isEmpty { reselectPaths = paths }
    }

    /// Shows the last of `paths` selected on the Sets tab.
    private func select(_ paths: [String]) {
        guard let last = paths.last else { return }
        searchText = ""
        tab = .sets
        selectedSetPath = last
    }

    func takePendingOpenPaths() -> [String] {
        defer { pendingOpenPaths = [] }
        return pendingOpenPaths
    }

    func openInLive(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            toast(CommonStrings.pathMissing.f(path), kind: .error)
            return
        }
        Task { [weak self] in
            do {
                try await LiveLauncher.open(setAt: path)
            } catch {
                self?.report(error, failure: CommonStrings.liveOpenFailed)
            }
        }
    }

    func launchLive() {
        Task { [weak self] in
            do {
                try await LiveLauncher.launch()
            } catch {
                self?.report(error, failure: CommonStrings.liveLaunchFailed)
            }
        }
    }

    func revealInFinder(path: String) {
        do {
            try Finder.reveal(path: path)
        } catch {
            report(error, failure: CommonStrings.folderOpenFailed)
        }
    }

    func togglePin(path: String) {
        home.togglePin(path: path)
    }

    func playPauseContextual() {
        if tab == .samples {
            samples.togglePlaySelected()
        } else {
            player.togglePlayPause()
        }
    }

    func rescan() {
        if tab == .samples {
            samples.rescan()
        } else {
            catalog.rescan()
        }
    }

    func presentFilters() {
        switch tab {
        case .sets: sheet = .filters
        case .plugins: sheet = .pluginFilters
        case .home, .samples: break
        }
    }

    func presentScanFolders() {
        sheet = .roots(tab == .samples ? .samples : .projects)
    }

    func presentHelp() { sheet = .help }

    func presentTags() { withSelectedSet { sheet = .tags(path: $0) } }
    func presentPreview() { withSelectedSet { sheet = .preview(path: $0) } }
    func presentRescue() { withSelectedSet { sheet = .rescue(path: $0) } }
    func presentExport() { withSelectedSet { sheet = .export(path: $0) } }
    func openSelectedInLive() { withSelectedSet { openInLive(path: $0) } }
    func revealSelectedInFinder() {
        if tab == .plugins {
            if let row = plugins.selectedRow { plugins.reveal(row) }
        } else {
            withSelectedSet { revealInFinder(path: $0) }
        }
    }
    func togglePinSelected() { withSelectedSet { togglePin(path: $0) } }

    func focusSearch() { searchFocusRequest += 1 }

    // MARK: - Internals

    private func withSelectedSet(_ body: (String) -> Void) {
        guard let path = selectedSetPath else { return }
        body(path)
    }

    /// Shows a service error as a toast using `failure` as the "%@" format.
    private func report(_ error: Error, failure: CommonStrings) {
        switch error {
        case LiveLauncherError.notInstalled:
            toast(CommonStrings.liveNotFound.s, kind: .error)
        case LiveLauncherError.failed(let reason):
            toast(failure.f(reason), kind: .error)
        case FinderError.missing(let path), FinderError.failed(let path):
            toast(CommonStrings.pathMissing.f(path), kind: .error)
        default:
            toast(failure.f(error.localizedDescription), kind: .error)
        }
    }
}
