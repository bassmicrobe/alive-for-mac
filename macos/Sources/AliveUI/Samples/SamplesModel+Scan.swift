// Mac-only: loading the cache and walking the sample folders in the background (upstream:
// MainForm.StartSampleScan / RescanSamples / LoadSamplesFromCache in src/SamplesTab.cs).
import Foundation
import AliveCore

/// Set from the main actor, read by the walk on its own thread.
final class SampleCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Passes the walk's running total to the main actor at most every 150 ms.
private final class SampleProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    private let deliver: @Sendable (Int) -> Void

    init(_ deliver: @escaping @Sendable (Int) -> Void) { self.deliver = deliver }

    func report(_ n: Int) {
        lock.lock()
        let now = Date()
        let due = now.timeIntervalSince(last) >= 0.15
        if due { last = now }
        lock.unlock()
        if due { deliver(n) }
    }
}

/// Runs blocking work on a dedicated queue instead of the cooperative pool, whose few threads a
/// long folder walk would otherwise hold (starving every other async task).
private enum SampleWalkQueue {
    static let queue = DispatchQueue(label: "alive.samples.walk", qos: .utility)

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: work()) }
        }
    }
}

extension SamplesModel {
    /// Loads `samples.cache` (off the main thread) and shows it at once, then walks the folders
    /// quietly. Idempotent; the view calls it when the tab appears.
    func start() {
        guard !started else { return }
        started = true
        let dir = app.dataDir
        loadTask = Task { [weak self] in
            let cached = await Task.detached(priority: .userInitiated) { SampleCache.load(dir: dir) }.value
            guard let self else { return }
            let s = self.app.settings
            self.adopt(cached.only(s.sampleRoots, disabled: s.disabledSampleRoots))
            self.isLoaded = true
            // A folder the cache knows is shown at once; one it does not waits for the walk.
            if let path = self.pendingReveal, !self.hasEnabledRoots || self.knows(folder: path) {
                self.pendingReveal = nil
                self.reveal(path)
            }
            self.syncRoots(force: true, manual: false)
        }
    }

    /// The list of folders changed (added, removed, switched on or off in the roots sheet): the tree
    /// follows at once, the walk follows behind. A no-op when nothing that counts changed.
    func syncRoots(force: Bool = false, manual: Bool = true) {
        guard started, isLoaded else { return }
        let roots = effectiveRoots
        let key = roots.joined(separator: "\n")
        guard force || key != scannedKey else { return }
        scannedKey = key
        if roots.isEmpty {
            scanFlag?.cancel()
            restartRequested = false
            adopt(.empty)
            return
        }
        adopt(index.only(app.settings.sampleRoots, disabled: app.settings.disabledSampleRoots))
        startScan(manual: manual)
    }

    func adopt(_ fresh: SampleIndex) {
        index = fresh
        indexGeneration += 1
        estimate = fresh.totalSamples
        if expandsRootsOnFirstLoad, !fresh.roots.isEmpty {
            expandsRootsOnFirstLoad = false
            openFolders.formUnion(fresh.roots.map { fresh.folders[$0].path.lowercased() })
            openRevision += 1
        }
        // The selection stays when its row is still there; otherwise the panel would show a ghost.
        if let sel = selection, kind(ofRow: sel) == nil {
            selection = nil
            info = nil
        }
    }

    /// Walks the enabled folders in the background. A walk already under way is called off and
    /// started again — it would have walked yesterday's list of folders.
    func startScan(manual: Bool) {
        if isScanning {
            restartRequested = true
            scanFlag?.cancel()
            return
        }
        let s = app.settings
        let roots = s.sampleRoots, off = s.disabledSampleRoots
        guard !SampleIndex.effective(roots, disabled: off).isEmpty else { adopt(.empty); return }

        isScanning = true
        isManualScan = manual
        found = 0
        estimate = index.totalSamples
        let flag = SampleCancelFlag()
        scanFlag = flag
        let previous = index, dir = app.dataDir
        let relay = SampleProgressRelay { [weak self] n in
            Task { @MainActor in
                guard let self, self.isScanning else { return }
                self.found = n
            }
        }

        scanTask = Task { [weak self] in
            let began = Date()
            let fresh = await SampleWalkQueue.run { () -> SampleIndex? in
                let built = SampleIndex.build(roots: roots, disabled: off, previous: previous,
                                              progress: relay.report, isCancelled: { flag.isCancelled })
                guard !flag.isCancelled else { return nil }
                SampleCache.save(built, dir: dir)
                return built
            }
            guard let self else { return }
            self.isScanning = false
            if let fresh {
                self.adopt(fresh)
                Diag.info("samples: \(fresh.totalSamples) in \(fresh.folders.count) folders, "
                          + "\(Int(Date().timeIntervalSince(began) * 1000)) ms")
            }
            if self.restartRequested {
                self.restartRequested = false
                self.startScan(manual: true)
            } else if let path = self.pendingReveal {
                self.pendingReveal = nil
                self.reveal(path)
            }
        }
    }

    func knows(folder path: String) -> Bool {
        if case .folder? = kind(ofRow: SampleIndex.norm(path)) { return true }
        return false
    }

    /// `showFolder` after the index is there.
    func reveal(_ path: String) {
        let standard = SampleIndex.norm(path)
        if case .folder = kind(ofRow: standard) {
            showInTree(standard)
        } else {
            lens = .all
            select(nil)
            outsideFolder = standard          // the panel says it is not in the library
        }
    }
}
