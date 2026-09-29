// Port of src/ProjectIndex.cs (catalog + scan). Cache in IndexCache.swift, SetEntry/PluginStat in
// SetEntry.swift, plugin summaries in ProjectIndex+Plugins.swift, per-set build in SetBuilder.swift.
import Foundation

/// `progress(done, total, current)`; total = 0 means "how many there are is not known yet"
/// (the folder walk is still going). Called from background threads.
public typealias ScanProgress = @Sendable (_ done: Int, _ total: Int, _ current: String) -> Void

/// What one scan did — useful for the UI's status line and for tests.
public struct ScanStats: Equatable, Sendable {
    public var total = 0
    /// Sets parsed from the .als this time.
    public var parsed = 0
    /// Sets taken from the cache because size and mtime were unchanged.
    public var reused = 0
    public var cancelled = false
    public var seconds = 0.0
}

/// The catalog of sets. Parsing one set takes around 100 ms and there are thousands of them, so
/// the result is cached to disk and reused until the file changes.
///
/// Threading: every accessor returns an immutable snapshot (value types), so the UI can read
/// while a scan runs. `scan` is a **blocking** call meant to run off the main thread (it uses a
/// bounded pool of `activeProcessorCount` workers); `scanAsync(...)` wraps it with task
/// cancellation. Progress callbacks arrive on background threads. A scan publishes the new
/// catalog with a single assignment at the end — until then readers keep the previous one.
public final class ProjectIndex: @unchecked Sendable {
    /// The data folder (index.cache, activity.cache live here).
    public let dir: String
    /// Injectable for tests: the home directory Live's preferences are looked up in.
    public let home: String
    /// Injectable for tests: where Live apps are searched (default /Applications, ~/Applications).
    public let applicationsDirs: [String]?

    let lock = NSLock()
    var _sets: [SetEntry] = []
    var _env = LiveEnvironment()
    var _history = Activity.empty
    var _inventory = PluginInventory()
    var _settings: Settings
    var _generation = 0                       // bumps whenever sets or inventory change
    var _usageCache: (generation: Int, list: [PluginStat])?
    var _vendorCache: (generation: Int, set: Set<String>)?
    var _lastStats = ScanStats()

    /// The inventory source; the default is `PluginInventory.load(settings:)`.
    public var inventoryLoader: @Sendable (Settings) -> PluginInventory = { PluginInventory.load(settings: $0) }

    public init(dir: String = AppHome.path, home: String = NSHomeDirectory(),
                applicationsDirs: [String]? = nil, settings: Settings? = nil) {
        self.dir = dir
        self.home = home
        self.applicationsDirs = applicationsDirs
        self._settings = settings ?? Settings.load(dir: dir)
    }

    // MARK: snapshots

    /// The catalog of sets (a snapshot; a published array is never modified).
    public var sets: [SetEntry] { lock.lock(); defer { lock.unlock() }; return _sets }
    public var env: LiveEnvironment { lock.lock(); defer { lock.unlock() }; return _env }
    /// When the work happened — the history of saves from the Backup folders.
    public var history: Activity { lock.lock(); defer { lock.unlock() }; return _history }
    /// What is installed on the machine.
    public var inventory: PluginInventory { lock.lock(); defer { lock.unlock() }; return _inventory }
    public var lastScanStats: ScanStats { lock.lock(); defer { lock.unlock() }; return _lastStats }
    /// Settings the plugin inventory is loaded with; set it when the user changes them.
    public var settings: Settings {
        get { lock.lock(); defer { lock.unlock() }; return _settings }
        set { lock.lock(); _settings = newValue; lock.unlock() }
    }

    // MARK: loading and scanning

    /// Loads the cache instantly at launch. False when there is none.
    @discardableResult
    public func loadFromCache() -> Bool {
        let cache = IndexCache.load(dir: dir)
        guard !cache.isEmpty else { return false }
        let list = cache.values.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let history = Activity.loadCache(dir: dir)
        lock.lock()
        _sets = list; _history = history; _generation += 1
        lock.unlock()
        refreshInstalled()
        return true
    }

    /// Scans the roots in the settings (`settings.roots` minus `disabledRoots`).
    @discardableResult
    public func scan(settings s: Settings, progress: ScanProgress? = nil,
                     isCancelled: @escaping @Sendable () -> Bool = { false }) -> ScanStats {
        settings = s
        return scan(roots: s.roots, disabledRoots: s.disabledRoots, progress: progress, isCancelled: isCancelled)
    }

    /// Async wrapper: runs the blocking scan on a background task; cancelling the calling task
    /// stops the scan at the next set.
    @discardableResult
    public func scanAsync(roots: [String], disabledRoots: [String] = [], progress: ScanProgress? = nil) async -> ScanStats {
        // A dedicated queue, not the cooperative pool: the scan blocks for a long time.
        await BlockingWork.run { [self] isCancelled in
            scan(roots: roots, disabledRoots: disabledRoots, progress: progress, isCancelled: isCancelled)
        }
    }

    /// Blocking scan. Files whose size and mtime are unchanged are taken from the cache; the rest
    /// are parsed in parallel. Renders, project weights, activity and plugin health are rebuilt
    /// on every scan (they change without the .als changing).
    @discardableResult
    public func scan(roots: [String], disabledRoots: [String] = [], progress: ScanProgress? = nil,
                     isCancelled: @escaping () -> Bool = { false }) -> ScanStats {
        let started = Date()
        let probe = ProbeCache()          // lives for exactly one scan: "rescan" must check again
        let env = LiveEnvironment.detect(home: home, applicationsDirs: applicationsDirs)
        lock.lock(); _env = env; lock.unlock()

        let files = collectFiles(roots: roots, disabledRoots: disabledRoots, progress: progress, isCancelled: isCancelled)
        let cache = IndexCache.load(dir: dir)
        var stats = ScanStats()
        stats.total = files.count

        let counters = Counters()
        let results: [SetEntry?] = Parallel.map(count: files.count, isCancelled: isCancelled) { i in
            let entry = self.entry(for: files[i], cache: cache, env: env, probe: probe, counters: counters)
            let n = counters.done()
            if let progress, n % 8 == 0 || n == files.count { progress(n, files.count, entry.name) }
            return entry
        }
        stats.parsed = counters.parsed
        stats.reused = counters.reused
        stats.cancelled = isCancelled()

        // A cancelled scan publishes nothing: a partial list would replace the catalog and the
        // cache with a fragment of it.
        if stats.cancelled {
            stats.seconds = Date().timeIntervalSince(started)
            return stats
        }

        var fresh = results.compactMap { $0 }
        // Each phase below stops early when cancelled and leaves partial data behind, so the
        // flag is looked at again after every one of them: nothing half-built is published or
        // written to the caches.
        func abandoned() -> Bool {
            guard isCancelled() else { return false }
            stats.cancelled = true
            stats.seconds = Date().timeIntervalSince(started)
            return true
        }
        addRenders(&fresh, isCancelled: isCancelled)
        if abandoned() { return stats }
        let known = history.total > 0 ? history : Activity.loadCache(dir: dir)
        let activity = weighProjects(&fresh, known: known, isCancelled: isCancelled)
        if abandoned() { return stats }

        // Publish the catalog whole; readers saw the previous one until this moment.
        lock.lock()
        _sets = fresh; _history = activity; _generation += 1
        lock.unlock()
        activity.saveCache(dir: dir)
        IndexCache.save(fresh, dir: dir)
        refreshInstalled()
        progress?(fresh.count, files.count, "")

        stats.seconds = Date().timeIntervalSince(started)
        lock.lock(); _lastStats = stats; lock.unlock()
        Diag.info("scan: \(stats.total) sets, \(stats.parsed) parsed, \(stats.reused) cached, "
                  + String(format: "%.2fs", stats.seconds))
        return stats
    }

    /// Walks each enabled root. One and the same .als turns up twice easily when roots are
    /// nested ("~/Music" and "~/Music/Ableton"): without the `seen` filter the set would double.
    private func collectFiles(roots: [String], disabledRoots: [String], progress: ScanProgress?,
                              isCancelled: () -> Bool) -> [String] {
        let disabled = Set(disabledRoots.map { $0.lowercased() })
        var files: [String] = []
        var seen = Set<String>()
        for root in roots where !disabled.contains(root.lowercased()) {   // temporarily off: stays in the list
            let before = files.count
            let r = FolderScan.find(root: root, ext: ".als", includeBackups: false, onFile: { f in
                guard seen.insert(f.lowercased()).inserted else { return }
                files.append(f)
                if files.count % 16 == 0 { progress?(files.count, 0, f) }
            }, isCancelled: isCancelled)
            Diag.info("scan: \(root) -> \(files.count - before) sets in \(r.dirs) folders"
                      + (r.unreadable > 0 ? ", \(r.unreadable) folders unreadable" : "")
                      + (r.rootFailed ? "  ROOT NOT READABLE" : ""))
        }
        return files.sorted { $0.lowercased() < $1.lowercased() }
    }

    private func entry(for file: String, cache: [String: SetEntry], env: LiveEnvironment,
                       probe: ProbeCache, counters: Counters) -> SetEntry {
        guard let stamp = SetBuilder.stamp(of: file) else {
            counters.failed()
            return SetBuilder.failed(path: file, error: "cannot read file attributes")
        }
        if let cached = cache[file.lowercased()], cached.size == stamp.size,
           DotNetTicks.sameInstant(cached.modified, stamp.modified) {
            counters.reuse()
            return cached                          // the file has not changed — take it from the cache
        }
        counters.parse()
        return SetBuilder.build(path: file, stamp: stamp, env: env, probe: probe)
    }

    /// Renders are a property of the folder rather than of the set, so they go in a separate pass
    /// and do not get into the cache: exporting a new file does not change the .als. Their names
    /// are remembered so a set can be searched by the name of a render.
    private func addRenders(_ sets: inout [SetEntry], isCancelled: () -> Bool) {
        let snapshot = sets
        let pins = PreviewPins(dir: dir)
        let found: [[String]?] = Parallel.map(count: snapshot.count, isCancelled: isCancelled) { i in
            RenderScan.find(snapshot[i], pins: pins).map(\.name)
        }
        for i in sets.indices {
            let names = found[i] ?? []
            sets[i].renderNames = names
            sets[i].hasRenders = !names.isEmpty
        }
    }

    /// The folder weight of each project. We count by DISTINCT folders rather than by sets: one
    /// project folder usually holds a dozen .als versions, and walking it for each would mean
    /// re-reading the same tree ten times. The save history arrives by the same walk.
    private func weighProjects(_ sets: inout [SetEntry], known: Activity,
                               isCancelled: () -> Bool) -> Activity {
        var dirs: [String] = []
        var slot: [String: Int] = [:]
        for s in sets {
            let d = s.projectDir
            if d.isEmpty || slot[d.lowercased()] != nil { continue }
            slot[d.lowercased()] = dirs.count
            dirs.append(d)
        }
        let weighed: [FolderScan.Weight?] = Parallel.map(count: dirs.count, isCancelled: isCancelled) { i in
            FolderScan.weigh(root: dirs[i], isCancelled: isCancelled)
        }
        let weights = weighed.map { $0 ?? FolderScan.Weight() }
        for i in sets.indices {
            guard let k = slot[sets[i].projectDir.lowercased()] else { continue }
            sets[i].projectSize = weights[k].bytes
            sets[i].projectFiles = weights[k].files
        }
        return Activity.build(dirs: dirs, weights: weights, sets: sets, previous: known)
    }

    // MARK: grouping

    /// One row per folder. A project usually has a dozen .als files lying next to each other —
    /// v1, v2, final, final2 — and in the catalog they take ten rows although the project is
    /// one. We keep the newest and hide the rest under it, writing how many are hidden into its
    /// `collapsedCount`.
    ///
    /// We collapse AFTER the filters and the search, not before: otherwise a query for a plugin
    /// that survives only in an older version would find nothing at all.
    public static func collapseByFolder(_ matched: [SetEntry]) -> [SetEntry] {
        var order: [SetEntry] = []
        order.reserveCapacity(matched.count)
        var slot: [String: Int] = [:]
        for var s in matched {
            s.collapsedCount = 0
            let key = s.directory.lowercased()
            guard let i = slot[key] else {
                slot[key] = order.count
                order.append(s)
                continue
            }
            if s.modified > order[i].modified {
                s.collapsedCount = order[i].collapsedCount + 1   // the counter moves to the new principal one
                order[i] = s
            } else {
                order[i].collapsedCount += 1
            }
        }
        return order
    }

    /// Every set from the same folder, newest first — including the one passed in. The details
    /// panel needs it: what is hidden under a collapsed row has to be visible.
    public func inSameFolder(_ s: SetEntry) -> [SetEntry] {
        let dir = s.directory.lowercased()
        return sets.filter { $0.directory.lowercased() == dir }.sorted { $0.modified > $1.modified }
    }
}

/// Thread-safe progress counters for one scan.
final class Counters: @unchecked Sendable {
    private let lock = NSLock()
    private var doneCount = 0, parsedCount = 0, reusedCount = 0

    func done() -> Int { lock.lock(); defer { lock.unlock() }; doneCount += 1; return doneCount }
    func parse() { lock.lock(); parsedCount += 1; lock.unlock() }
    func reuse() { lock.lock(); reusedCount += 1; lock.unlock() }
    func failed() { lock.lock(); parsedCount += 1; lock.unlock() }
    var parsed: Int { lock.lock(); defer { lock.unlock() }; return parsedCount }
    var reused: Int { lock.lock(); defer { lock.unlock() }; return reusedCount }
}

/// Cancellation bridge from structured concurrency to the blocking scan.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func set() { lock.lock(); flag = true; lock.unlock() }
}
