// Mac-only glue for src/FolderWatch.cs: keeps a `FolderWatch` pointed at the enabled project roots
// and rescans the catalog when something changed there. Follows edits of the root list on its own
// (Observation), so the only hook it needs is `app.sets.watcher.start()` in `CatalogModel.start()`.
import Foundation
import Observation
import AliveCore

@MainActor
final class CatalogWatcher {
    private unowned let app: AppModel
    private let watch: FolderWatch
    private var started = false
    private var retry: Task<Void, Never>?
    /// How long to wait before asking again while a scan is still running.
    private let retryDelay: Duration

    init(app: AppModel, watch: FolderWatch = FolderWatch(), retryDelay: Duration = .seconds(3)) {
        self.app = app
        self.watch = watch
        self.retryDelay = retryDelay
    }

    /// Idempotent.
    func start() {
        guard !started else { return }
        started = true
        watch.onChanged = { [weak self] in
            Task { @MainActor in self?.diskChanged() }
        }
        rewatch()
        observeRoots()
    }

    func stop() {
        started = false
        retry?.cancel()
        watch.stop()
    }

    // MARK: - Roots

    private func rewatch() {
        watch.watch(roots: app.settings.roots, disabled: app.settings.disabledRoots)
    }

    /// Re-arms itself: `withObservationTracking` fires once per change.
    private func observeRoots() {
        guard started else { return }
        withObservationTracking {
            _ = app.settings.roots
            _ = app.settings.disabledRoots
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.started else { return }
                self.rewatch()
                self.observeRoots()
            }
        }
    }

    // MARK: - Changes

    /// The disk has been quiet for a while after a change: rescan. A running scan is not
    /// interrupted; ask again once it is done (its result may already be stale).
    func diskChanged() {
        guard started else { return }
        guard app.catalog.isReady else {
            retry?.cancel()
            retry = Task { [weak self, retryDelay] in
                try? await Task.sleep(for: retryDelay)
                guard !Task.isCancelled else { return }
                self?.diskChanged()
            }
            return
        }
        Diag.info("folder watch: change on disk, rescanning")
        app.catalog.rescan()
    }
}
