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
    /// What the watch is pointed at now; unrelated settings changes must not re-arm it (that
    /// would cancel a pending debounced rescan).
    private var watched: WatchedRoots?
    /// Arming looks at the disk (exists? real path?), which can be slow on network volumes.
    private let armQueue = DispatchQueue(label: "alive.catalogwatcher.arm", qos: .utility)
    /// How many times the watch was re-pointed (for tests).
    private(set) var armCount = 0

    private struct WatchedRoots: Equatable {
        let roots: [String]
        let disabled: [String]
    }
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
        watched = nil
        let watch = watch
        armQueue.async { watch.stop() }
    }

    /// Waits for pending arming work (for tests).
    func waitUntilArmed() { armQueue.sync {} }

    // MARK: - Roots

    private func rewatch() {
        let next = WatchedRoots(roots: app.settings.roots, disabled: app.settings.disabledRoots)
        guard next != watched else { return }
        watched = next
        armCount += 1
        let watch = watch
        armQueue.async { watch.watch(roots: next.roots, disabled: next.disabled) }
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
