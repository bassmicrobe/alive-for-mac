// Mac-only: wraps the core `ProjectIndex` (upstream MainForm's scan plumbing). Loads the cache
// off the main thread and publishes it at once, then rescans in the background; owns the project
// root list edits. All published state lives on the main actor.
import Foundation
import Observation
import AliveCore

/// Where a running scan is. `total == 0` means the folder walk has not finished counting.
struct CatalogProgress: Equatable {
    var done = 0
    var total = 0
    var current = ""

    /// 0...1 once the total is known.
    var fraction: Double? { total > 0 ? min(1, Double(done) / Double(total)) : nil }
}

@MainActor
@Observable
final class CatalogModel {
    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored let index: ProjectIndex

    /// Every set of the scanned roots.
    private(set) var sets: [SetEntry] = []
    /// `sets`, one row per folder when `settings.groupByFolder` (newest set on top, the rest
    /// counted in `collapsedCount`), like upstream's default list.
    private(set) var projects: [SetEntry] = []
    private(set) var env = LiveEnvironment()
    private(set) var history = Activity.empty
    private(set) var isScanning = false
    private(set) var progress = CatalogProgress()
    private(set) var lastScanStats: ScanStats?
    /// The cache has been read (or there was nothing to read): what is published is meaningful.
    private(set) var isLoaded = false
    /// Bumped on every publish; lets dependants memoize.
    private(set) var revision = 0

    @ObservationIgnored private var started = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// The next scan has to walk every project (its weight and Backup history).
    @ObservationIgnored private var fullPending = true
    /// A rescan was asked for before the cache was read: it runs right after, so the cache can
    /// neither be published over a fresh result nor be read while a scan writes the index.
    @ObservationIgnored private var rescanAfterLoad = false

    init(app: AppModel) {
        self.app = app
        self.index = ProjectIndex(dir: app.dataDir, settings: app.settings)
    }

    /// The catalog can be asked things: the cache is in and no scan is running.
    var isReady: Bool { isLoaded && !isScanning }

    var hasEnabledRoots: Bool {
        let s = app.settings
        return s.roots.contains { root in !s.disabledRoots.contains { Self.same($0, root) } }
    }

    // MARK: - Launch

    /// Loads the cache (off the main thread), publishes it, then scans when there are roots.
    /// Idempotent.
    func start() {
        guard !started else { return }
        started = true
        let index = index
        Task { [weak self] in
            // The catalog is published straight from the cache; plug-in discovery comes after it
            // (the scan that follows does it once at its end — with no roots there is no scan,
            // so it is done here).
            let detected = await Task.detached(priority: .userInitiated) { () -> LiveEnvironment in
                index.loadFromCache(refreshInventory: false)
                return LiveEnvironment.detect()
            }.value
            guard let self else { return }
            self.isLoaded = true
            self.publish(fallbackEnv: detected)
            if self.hasEnabledRoots || self.rescanAfterLoad {
                self.rescanAfterLoad = false
                self.rescan()
            } else {
                await Task.detached(priority: .userInitiated) { index.refreshInstalled() }.value
                self.publish(fallbackEnv: detected)
                self.app.catalogDidBecomeReady()
            }
        }
    }

    // MARK: - Scanning

    /// Cancels a running scan and starts a new one over the current roots. `full: false` (a
    /// folder-watch rescan) skips walking the weight and Backup history of projects whose sets
    /// did not change; every other rescan reads them all.
    func rescan(full: Bool = true) {
        guard started else { return }
        guard isLoaded else {
            rescanAfterLoad = true
            return
        }
        generation += 1
        let gen = generation
        let previous = scanTask
        previous?.cancel()
        isScanning = true
        progress = CatalogProgress()
        // A full request stays pending until a scan that asked for it completes.
        if full { fullPending = true }
        let fullRescan = fullPending

        let settings = app.settings
        let index = index
        index.settings = settings
        scanTask = Task { [weak self] in
            // Two scans on one index would fight over the cache file: wait for the old one to stop.
            await previous?.value
            guard let self, gen == self.generation else { return }
            let stats = await index.scanAsync(
                roots: settings.roots, disabledRoots: settings.disabledRoots,
                progress: { done, total, current in
                    Task { @MainActor in
                        self.updateProgress(gen, CatalogProgress(done: done, total: total, current: current))
                    }
                },
                fullRescan: fullRescan)
            self.finishScan(gen, stats)
        }
    }

    private func updateProgress(_ gen: Int, _ next: CatalogProgress) {
        guard gen == generation, isScanning else { return }
        // Updates hop threads and can arrive out of order; the count only grows within one scan.
        if next.total == progress.total, next.done < progress.done { return }
        progress = next
    }

    private func finishScan(_ gen: Int, _ stats: ScanStats) {
        guard gen == generation else { return }   // superseded: the newer scan reports
        lastScanStats = stats
        if !stats.cancelled && !stats.retainedPreviousCatalog { fullPending = false }
        isScanning = false
        progress = CatalogProgress()
        publish()
        Diag.info("catalog: \(stats.total) sets (\(stats.parsed) parsed, \(stats.reused) cached) in "
                  + String(format: "%.1f", stats.seconds) + " s" + (stats.cancelled ? ", cancelled" : "")
                  + (stats.retainedPreviousCatalog ? ", previous catalog retained" : ""))
        app.catalogDidBecomeReady()
    }

    /// Copies the index's snapshots into the published state.
    private func publish(fallbackEnv: LiveEnvironment? = nil) {
        let all = hasEnabledRoots ? index.sets : []
        sets = all
        projects = app.settings.groupByFolder ? ProjectIndex.collapseByFolder(all) : all
        let scanned = index.env
        env = scanned.userLibrary.isEmpty ? (fallbackEnv ?? scanned) : scanned
        history = index.history
        revision += 1
    }

    /// Re-derives `projects` after a setting such as `groupByFolder` changed.
    func settingsDidChange() {
        projects = app.settings.groupByFolder ? ProjectIndex.collapseByFolder(sets) : sets
        revision += 1
    }

    // MARK: - Roots

    /// Adds folders to scan (a file counts as its folder), saves and rescans. Returns the folders
    /// that were new. Toasts the outcome.
    @discardableResult
    func addRoots(_ paths: [String]) -> [String] {
        var added: [String] = []
        var settings = app.settings
        for raw in paths {
            let folder = Self.folder(of: raw)
            guard RootSuggestions.directoryExists(folder) else {
                app.toast(CommonStrings.notAFolder.f(raw), kind: .error)
                continue
            }
            settings.disabledRoots.removeAll { Self.same($0, folder) }
            if settings.roots.contains(where: { Self.same($0, folder) }) { continue }
            settings.roots.append(folder)
            added.append(folder)
        }
        guard !added.isEmpty else {
            if !paths.isEmpty { app.toast(CommonStrings.alreadyWatching.s) }
            return []
        }
        commit(settings)
        let names = added.map { ($0 as NSString).lastPathComponent }
        app.toast(added.count == 1 ? CommonStrings.rootAdded.f(names[0]) : CommonStrings.rootsAdded.f(added.count))
        return added
    }

    @discardableResult
    func addRoot(_ path: String) -> Bool { !addRoots([path]).isEmpty }

    func removeRoot(_ path: String) {
        var settings = app.settings
        settings.roots.removeAll { Self.same($0, path) }
        settings.disabledRoots.removeAll { Self.same($0, path) }
        commit(settings)
    }

    /// Turns a root off without forgetting it (upstream: the checkbox in the folders window).
    func setRoot(_ path: String, enabled: Bool) {
        var settings = app.settings
        guard settings.roots.contains(where: { Self.same($0, path) }) else { return }
        settings.disabledRoots.removeAll { Self.same($0, path) }
        if !enabled { settings.disabledRoots.append(path) }
        commit(settings)
    }

    private func commit(_ settings: AppSettings) {
        app.mutateSettings { $0 = settings }
        rescan()
    }

    // MARK: - Helpers

    static func folder(of path: String) -> String {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let folder = exists && !isDir.boolValue ? (path as NSString).deletingLastPathComponent : path
        return (folder as NSString).standardizingPath
    }

    static func same(_ a: String, _ b: String) -> Bool {
        (a as NSString).standardizingPath.caseInsensitiveCompare((b as NSString).standardizingPath) == .orderedSame
    }
}
