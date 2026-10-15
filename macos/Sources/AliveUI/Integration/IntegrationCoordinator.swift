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
    private let finderTags: FinderTagWorker
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
        finderTags = FinderTagWorker(dataDir: app.dataDir)
        if app.settings.finderTags { finderTags.gate.enable() }
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
        refreshFinderTags()
        if let path = pendingLink { pendingLink = nil; showInAlive(path: path) }
    }

    func settingsDidChange(from old: AppSettings) {
        let now = app.settings
        if now.spotlight != old.spotlight || now.lang != old.lang { refreshSpotlight() }
        if now.finderTags != old.finderTags {
            if now.finderTags {
                finderTags.gate.enable()
                refreshFinderTags()
            } else {
                finderTags.gate.disable()   // queued and running writes stop at the next folder
            }
        }
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
            previous?.cancel()
            syncTask = Task {
                await previous?.value
                guard !Task.isCancelled else { return }
                await indexer.removeEverything()
                if let text = SpotlightDebugQuery.text { SpotlightDebugQuery.logMatches(for: text) }
            }
            return
        }
        // Nothing to say before the first publish: an empty catalog would clear the index.
        guard app.catalog.isLoaded else { return }
        previous?.cancel()
        let sets = app.catalog.sets
        let meta = app.sets.meta
        // Read on the main actor; the detached work formats with these immutable inputs only.
        let lang = Localizer.shared.lang
        let locale = Localizer.shared.locale
        syncTask = Task.detached(priority: .utility) {
            await previous?.value
            guard !Task.isCancelled else { return }
            var documents: [SpotlightDocument] = []
            documents.reserveCapacity(sets.count)
            for set in sets {
                guard !Task.isCancelled else { return }
                if let document = SpotlightDocument.make(for: set, tags: meta.tagsOf(set.projectDir),
                    description: SpotlightDocument.describe(set, lang: lang, locale: locale)) {
                    documents.append(document)
                }
            }
            guard !Task.isCancelled else { return }
            await indexer.sync(documents)
            guard !Task.isCancelled else { return }
            if let text = SpotlightDebugQuery.text { SpotlightDebugQuery.logMatches(for: text) }
        }
    }

    // MARK: Finder tags

    private func refreshFinderTags() {
        guard app.settings.finderTags, app.catalog.isLoaded, let ticket = finderTags.gate.begin() else { return }
        let worker = finderTags
        let meta = app.sets.meta
        let dirs = Set(app.catalog.sets.filter { !$0.isBackup }.map(\.projectDir))
        Task.detached(priority: .utility) {
            var desired: [String: [String]] = [:]
            for dir in dirs { desired[dir] = meta.tagsOf(dir) }
            await worker.run(desired: desired, ticket: ticket)
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
    /// Registered by the main window as soon as it exists (and by the menu bar content), so URL
    /// commands can reopen a closed window; SwiftUI's `openWindow` is only reachable from a view.
    static var openWindow: (() -> Void)?

    enum Step: Equatable { case raiseExisting, reopen, nothing }

    /// Pure decision: raise the window if there is one, else reopen it if an opener is registered.
    static func decide(hasMainWindow: Bool, hasOpener: Bool) -> Step {
        if hasMainWindow { return .raiseExisting }
        return hasOpener ? .reopen : .nothing
    }

    static func register(_ open: @escaping () -> Void) { openWindow = open }

    static func show() {
        if ProcessInfo.processInfo.environment["ALIVE_NO_ACTIVATE"] != "1" {
            NSApp.activate(ignoringOtherApps: true)
        }
        let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true })
        switch decide(hasMainWindow: window != nil, hasOpener: openWindow != nil) {
        case .raiseExisting:
            if window?.isMiniaturized == true { window?.deminiaturize(nil) }
            window?.makeKeyAndOrderFront(nil)
        case .reopen: openWindow?()
        case .nothing: break
        }
    }
}
