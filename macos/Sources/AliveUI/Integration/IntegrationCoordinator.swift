// Mac-only: ties the Mac integrations (Spotlight, Finder tags) to the app: reacts to catalog
// publishes, tag edits and the three toggles. AppModel owns one; every hook is a one-liner there.
import AppKit
import Foundation
import Observation
import AliveCore

@MainActor
final class IntegrationCoordinator {
    @ObservationIgnored private unowned let app: AppModel
    private let spotlight: SpotlightIndexer
    private let finderTags: FinderTagSync
    private var observing = false
    private var syncTask: Task<Void, Never>?
    /// Brings the main window forward; replaced in tests (there is no application there).
    var presentWindow: () -> Void = { MainWindowPresenter.show() }
    /// A set Spotlight asked for before the catalog could answer.
    private var pendingLink: String?

    /// `backend` nil: the real Core Spotlight index, except under XCTest, where the system index
    /// must never be touched.
    init(app: AppModel, backend: SpotlightBackend? = nil) {
        self.app = app
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        spotlight = SpotlightIndexer(dataDir: app.dataDir,
                                     backend: backend ?? (underTest ? NullSpotlightBackend() : CoreSpotlightBackend()))
        finderTags = FinderTagSync(dataDir: app.dataDir)
    }

    // MARK: hooks

    /// Once, after the app started: watch the tags.
    func start() {
        guard !observing else { return }
        observing = true
        observeTags()
    }

    /// The catalog was published (cache loaded or a scan ended).
    func catalogDidChange() {
        refreshSpotlight()
        if let path = pendingLink { pendingLink = nil; showInAlive(path: path) }
    }

    func settingsDidChange(from old: AppSettings) {
        let now = app.settings
        if now.spotlight != old.spotlight { refreshSpotlight() }
        if now.finderTags != old.finderTags, now.finderTags { refreshFinderTags() }
    }

    private func observeTags() {
        withObservationTracking {
            _ = app.sets.metaRevision
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.tagsDidChange()
                self.observeTags()
            }
        }
    }

    private func tagsDidChange() {
        refreshSpotlight()
        refreshFinderTags()
    }

    // MARK: Spotlight

    private func refreshSpotlight() {
        let indexer = spotlight
        let previous = syncTask
        guard app.settings.spotlight else {
            syncTask = Task { await previous?.value; await indexer.removeEverything() }
            return
        }
        // Nothing to say before the first publish: an empty catalog would clear the index.
        guard app.catalog.isLoaded else { return }
        let sets = app.catalog.sets
        let meta = app.sets.meta
        syncTask = Task.detached(priority: .utility) {
            await previous?.value
            let documents = sets.compactMap { set in
                SpotlightDocument.make(for: set, tags: meta.tagsOf(set.projectDir),
                                       description: SpotlightDocument.describe(set))
            }
            await indexer.sync(documents)
        }
    }

    // MARK: Finder tags

    private func refreshFinderTags() {
        guard app.settings.finderTags, app.catalog.isLoaded else { return }
        let sync = finderTags
        let meta = app.sets.meta
        let dirs = Set(app.catalog.sets.filter { !$0.isBackup }.map(\.projectDir))
        Task.detached(priority: .utility) {
            var desired: [String: [String]] = [:]
            for dir in dirs { desired[dir] = meta.tagsOf(dir) }
            sync.sync(desired: desired)
        }
    }

    // MARK: Spotlight result clicked / menu bar "Show in Alive"

    /// Shows the main window with `path` selected on the Sets tab. Before the catalog is ready the
    /// request waits for it; a set that is gone is reported.
    func showInAlive(path: String) {
        presentWindow()
        guard app.catalog.isReady else {
            pendingLink = path
            return
        }
        guard app.sets.set(at: path) != nil else {
            app.toast(CommonStrings.pathMissing.f(path), kind: .error)
            return
        }
        app.searchText = ""
        app.tab = .sets
        app.sets.select(path: path)
    }
}

/// Brings the main window forward, also when it was closed (the app keeps running for the menu bar).
@MainActor
enum MainWindowPresenter {
    /// Set by the menu bar content, which has SwiftUI's `openWindow`.
    static var openWindow: (() -> Void)?

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?()
        }
    }
}
