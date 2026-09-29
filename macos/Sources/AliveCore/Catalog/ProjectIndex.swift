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
    /// The decoded index.cache (with the file's stamp it was read at), reused by the next scan
    /// instead of decoding the file again.
    var _cacheMap: (stamp: FileStat?, entries: [String: SetEntry])?
    /// The weights of the last scan by lowercased project folder, with the sets they were taken
    /// for: a rescan that finds a folder's sets unchanged does not walk its tree again.
    var _weightMemo: [String: ProjectWeight] = [:]

    struct ProjectWeight {
        var weight: FolderScan.Weight
        var setPaths: Set<String>
    }

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

    /// Loads the cache instantly at launch. False when there is none. `refreshInventory: false`
    /// leaves the plug-in discovery to the caller (the catalog is visible first; the scan that
    /// follows does the discovery once, and `refreshInstalled()` can be called by hand).
    @discardableResult
    public func loadFromCache(refreshInventory: Bool = true) -> Bool {
        let cache = cachedEntries()
        guard !cache.isEmpty else { return false }
        let list = cache.values.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let history = Activity.loadCache(dir: dir)
        lock.lock()
        _sets = list; _history = history; _generation += 1
        lock.unlock()
        if refreshInventory { refreshInstalled() }
        return true
    }

    /// The decoded index.cache, from memory while the file is the one we read or wrote last.
    func cachedEntries() -> [String: SetEntry] {
        let stamp = FileStat.of(IndexCache.path(dir: dir))
        lock.lock()
        if let held = _cacheMap, held.stamp == stamp, stamp != nil { lock.unlock(); return held.entries }
        lock.unlock()
        let entries = IndexCache.load(dir: dir)
        lock.lock(); _cacheMap = (stamp, entries); lock.unlock()
        return entries
    }

    /// Scans the roots in the settings (`settings.roots` minus `disabledRoots`).
    @discardableResult
    public func scan(settings s: Settings, progress: ScanProgress? = nil, fullRescan: Bool = true,
                     isCancelled: @escaping @Sendable () -> Bool = { false }) -> ScanStats {
        settings = s
        return scan(roots: s.roots, disabledRoots: s.disabledRoots, progress: progress,
                    fullRescan: fullRescan, isCancelled: isCancelled)
    }

    /// Async wrapper: runs the blocking scan on a background task; cancelling the calling task
    /// stops the scan at the next set.
    @discardableResult
    public func scanAsync(roots: [String], disabledRoots: [String] = [], progress: ScanProgress? = nil,
                          fullRescan: Bool = true) async -> ScanStats {
        // A dedicated queue, not the cooperative pool: the scan blocks for a long time.
        await BlockingWork.run { [self] isCancelled in
            scan(roots: roots, disabledRoots: disabledRoots, progress: progress,
                 fullRescan: fullRescan, isCancelled: isCancelled)
        }
    }

    /// Blocking scan. Files whose size and mtime are unchanged are taken from the cache; the rest
    /// are parsed in parallel. Renders, activity and plugin health are rebuilt on every scan
    /// (they change without the .als changing). Project weights and Backup histories are walked
    /// for every project on a `fullRescan` (the default); otherwise only for projects whose sets
    /// changed since the previous scan of this index (the rest keep their last weight).
    @discardableResult
    public func scan(roots: [String], disabledRoots: [String] = [], progress: ScanProgress? = nil,
                     fullRescan: Bool = true, isCancelled: @escaping () -> Bool = { false }) -> ScanStats {
        let started = Date()
        let probe = ProbeCache()          // lives for exactly one scan: "rescan" must check again
        let env = LiveEnvironment.detect(home: home, applicationsDirs: applicationsDirs)
        lock.lock(); _env = env; lock.unlock()

        let files = collectFiles(roots: roots, disabledRoots: disabledRoots, progress: progress, isCancelled: isCancelled)
        let cache = cachedEntries()
        var stats = ScanStats()
        stats.total = files.count

        let counters = Counters()
        let built: [(entry: SetEntry, reused: Bool)?] = Parallel.map(count: files.count, isCancelled: isCancelled) { i in
            let r = self.entry(for: files[i], cache: cache, env: env, probe: probe, counters: counters,
                               isCancelled: isCancelled)
            let n = counters.done()
            if let progress, n % 8 == 0 || n == files.count { progress(n, files.count, r.entry.name) }
            return r
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

        var fresh = built.compactMap { $0?.entry }
        let changed = Set(built.compactMap { $0 }.filter { !$0.reused }.map { $0.entry.projectDir.lowercased() })
        // Each phase below stops early when cancelled and leaves partial data behind, so the
        // flag is looked at again after every one of them: nothing half-built is published or
        // written to the caches.
        func abandoned() -> Bool {
            guard isCancelled() else { return false }
            stats.cancelled = true
            stats.seconds = Date().timeIntervalSince(started)
            return true
        }
        let known = history.total > 0 ? history : Activity.loadCache(dir: dir)
        guard let walked = walkProjects(&fresh, changed: changed, full: fullRescan, isCancelled: isCancelled),
              !abandoned() else {
            _ = abandoned()
            return stats
        }
        let activity = Activity.build(dirs: walked.dirs, weights: walked.weights, sets: fresh, previous: known)

        // Publish the catalog whole; readers saw the previous one until this moment.
        lock.lock()
        _sets = fresh; _history = activity; _generation += 1
        _weightMemo = walked.memo
        lock.unlock()
        activity.saveCache(dir: dir)
        // The reuse map follows the file on disk: a failed save leaves it as it was.
        if IndexCache.save(fresh, dir: dir) != .failed { rememberCache(fresh) }
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

    /// After a save the file on disk is what `fresh` says: keep it as the next scan's reuse map.
    private func rememberCache(_ fresh: [SetEntry]) {
        var map: [String: SetEntry] = [:]
        map.reserveCapacity(fresh.count)
        for e in fresh { map[e.path.lowercased()] = e }
        let stamp = FileStat.of(IndexCache.path(dir: dir))
        lock.lock(); _cacheMap = (stamp, map); lock.unlock()
    }

    private func entry(for file: String, cache: [String: SetEntry], env: LiveEnvironment,
                       probe: ProbeCache, counters: Counters,
                       isCancelled: () -> Bool) -> (entry: SetEntry, reused: Bool) {
        guard let stamp = SetBuilder.stamp(of: file) else {
            counters.failed()
            return (SetBuilder.failed(path: file, error: "cannot read file attributes"), false)
        }
        if let cached = cache[file.lowercased()], cached.size == stamp.size,
           DotNetTicks.sameInstant(cached.modified, stamp.modified) {
            counters.reuse()
            return (cached, true)                  // the file has not changed — take it from the cache
        }
        counters.parse()
        return (SetBuilder.build(path: file, stamp: stamp, env: env, probe: probe, isCancelled: isCancelled), false)
    }

    /// What the walk of the project folders brought in, in the order of `dirs`.
    struct Walked {
        var dirs: [String]
        var weights: [FolderScan.Weight]
        var memo: [String: ProjectWeight]
    }

    /// One walk per DISTINCT project folder (a project usually holds a dozen .als versions; per
    /// set it would read the same tree ten times) gives the folder weight, the save history from
    /// Backup and the renders. Renders are a property of the folder rather than of the set, so
    /// they do not get into the cache: exporting a new file does not change the .als. Their
    /// names are remembered so a set can be searched by the name of a render. nil when cancelled.
    ///
    /// The weight (the expensive part: it reads Samples and Backup too) is taken from the
    /// previous scan for a folder whose sets are the same and unchanged, unless `full`.
    private func walkProjects(_ sets: inout [SetEntry], changed: Set<String>, full: Bool,
                              isCancelled: () -> Bool) -> Walked? {
        var dirs: [String] = []
        var slot: [String: Int] = [:]
        var pathsByDir: [String: Set<String>] = [:]
        for s in sets {
            let d = s.projectDir
            if d.isEmpty { continue }
            let key = d.lowercased()
            pathsByDir[key, default: []].insert(s.path.lowercased())
            if slot[key] != nil { continue }
            slot[key] = dirs.count
            dirs.append(d)
        }
        lock.lock(); let memo = full ? [:] : _weightMemo; lock.unlock()
        let pins = PreviewPins(dir: dir)
        let walked: [(weight: FolderScan.Weight, renders: [String])?] =
            Parallel.map(count: dirs.count, isCancelled: isCancelled) { i in
                let key = dirs[i].lowercased()
                var known: FolderScan.Weight?
                if !changed.contains(key), let m = memo[key], m.setPaths == pathsByDir[key] { known = m.weight }
                let r = FolderScan.walkProject(root: dirs[i], weigh: known == nil, renders: true,
                                               isCancelled: isCancelled)
                let names = RenderScan.finish(r.renders, root: dirs[i], pins: pins).map(\.name)
                return (known ?? r.weight, names)
            }
        if isCancelled() { return nil }
        let weights = walked.map { $0?.weight ?? FolderScan.Weight() }
        for i in sets.indices {
            guard let k = slot[sets[i].projectDir.lowercased()] else {
                sets[i].renderNames = []; sets[i].hasRenders = false
                continue
            }
            sets[i].projectSize = weights[k].bytes
            sets[i].projectFiles = weights[k].files
            let names = walked[k]?.renders ?? []
            sets[i].renderNames = names
            sets[i].hasRenders = !names.isEmpty
        }
        var newMemo: [String: ProjectWeight] = [:]
        for (i, d) in dirs.enumerated() {
            let key = d.lowercased()
            newMemo[key] = ProjectWeight(weight: weights[i], setPaths: pathsByDir[key] ?? [])
        }
        return Walked(dirs: dirs, weights: weights, memo: newMemo)
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
