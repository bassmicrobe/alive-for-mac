// Mac-only: the one app-wide model (docs/PORTING.md §8). Owns presentation state and one feature
// model per feature; contextual actions used by menus and toolbar live here.
import Foundation
import Observation

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
    /// Files handed to the app by Finder ("Open With"): consumed by wave 1.5.
    private(set) var pendingOpenPaths: [String] = []

    let prefs = AppPreferences()

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

    init() {}

    // MARK: - Toolbar state

    var shownCount: Int {
        switch tab {
        case .home: return home.shownCount
        case .sets: return sets.shownCount
        case .plugins: return plugins.shownCount
        case .samples: return samples.shownCount
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

    func openPaths(_ paths: [String]) {
        pendingOpenPaths.append(contentsOf: paths)
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
    func revealSelectedInFinder() { withSelectedSet { revealInFinder(path: $0) } }
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
