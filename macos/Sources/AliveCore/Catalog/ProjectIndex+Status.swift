// Mac-only: per-set status (offline volumes, plugin readiness, stale renders) kept beside the
// catalog. The facts behind it live in status.cache (StatusCache.swift); `SetStatus.derive` is the
// one place a status is worked out.
import Foundation

/// What a change of the mounted volumes means for the catalog.
public struct VolumeChange: Equatable, Sendable {
    public var mounted: Set<String>
    public var appeared: Set<String>
    public var disappeared: Set<String>
    /// Sets that had lost references on a volume that is mounted now: they have to be read again
    /// to find out whether those files are there.
    public var recheck: [String]

    public var isEmpty: Bool { appeared.isEmpty && disappeared.isEmpty }
}

extension ProjectIndex {
    // MARK: facts

    /// Reads status.cache (once) and the mount table; the statuses follow.
    func loadFacts() {
        let content = StatusCache.load(dir: dir)
        let mounted = mountProvider()
        lock.lock()
        _facts = content.sets
        _projectFacts = content.projects
        _factsLoaded = true
        _mounted = mounted
        lock.unlock()
    }

    /// The facts of the last scan (or of status.cache on disk when nothing has been scanned yet).
    func loadedFacts() -> StatusCacheContent {
        lock.lock()
        let loaded = _factsLoaded
        lock.unlock()
        if !loaded { loadFacts() }
        lock.lock(); defer { lock.unlock() }
        var content = StatusCacheContent()
        content.sets = _facts
        content.projects = _projectFacts
        return content
    }

    /// The facts a finished scan hands over: those of the project walks, and those of the sets
    /// that have something to say. A set with lost references always has a record, so a cached row
    /// without one is recognised as older than the offline/missing distinction.
    static func facts(built: [Built?], walked: Walked) -> StatusCacheContent {
        var out = StatusCacheContent()
        out.projects = walked.projects
        for b in built.compactMap({ $0 }) where b.entry.error.isEmpty {
            let e = b.entry
            let newest = walked.projects[e.projectDir.lowercased()]?.newestRenderTicks
            guard !b.offline.isEmpty || newest != nil || e.missingFiles > 0 else { continue }
            out.sets[e.path.lowercased()] = SetFacts(size: e.size, modifiedTicks: DotNetTicks.utc(e.modified),
                                                    offline: b.offline, newestRenderTicks: newest)
        }
        return out
    }

    static func weight(of kept: ProjectFacts) -> FolderScan.Weight {
        var w = FolderScan.Weight()
        w.bytes = kept.bytes
        w.files = kept.files
        // Only the names matter: the times are in activity.cache already (see ProjectFacts).
        if !kept.saveSets.isEmpty { w.saves = kept.saveSets.map { FolderScan.Save(when: .distantPast, set: $0) } }
        return w
    }

    static func projectFacts(_ w: FolderScan.Weight, renders: [String], newest: Int64?) -> ProjectFacts {
        var names = Set<String>()
        for s in w.saves ?? [] { names.insert(s.set.lowercased()) }
        return ProjectFacts(bytes: w.bytes, files: w.files, renders: renders, newestRenderTicks: newest,
                            saveSets: names.sorted())
    }

    // MARK: statuses

    /// Status by set path (O(1)); refreshed after every scan, inventory refresh and volume change.
    public var statuses: [String: SetStatus] { lock.lock(); defer { lock.unlock() }; return _statuses }

    /// References the sets lost because their volume was not mounted when they were read, by set
    /// path. A sample on a disconnected drive is still *used* by the set that points at it.
    public func offlineReferences() -> [String: [String]] {
        lock.lock(); defer { lock.unlock() }
        var out: [String: [String]] = [:]
        for e in _sets {
            guard let f = _facts[e.path.lowercased()], !f.offline.isEmpty, f.matches(e) else { continue }
            out[e.path] = f.offline
        }
        return out
    }

    /// Re-derives every status from the current sets, facts, mounted volumes and inventory.
    public func rebuildStatuses() {
        lock.lock()
        let sets = _sets, facts = _facts, known = _inventory.isAvailable
        let current = _mounted
        lock.unlock()
        let mounted = current ?? mountProvider()
        var map: [String: SetStatus] = [:]
        map.reserveCapacity(sets.count)
        for e in sets {
            let f = facts[e.path.lowercased()].flatMap { $0.matches(e) ? $0 : nil }
            map[e.path] = SetStatus.derive(entry: e, offlinePaths: f?.offline ?? [], newestRender: f?.newestRender,
                                           mounted: mounted, pluginsKnown: known)
        }
        lock.lock()
        _statuses = map
        if _mounted == nil { _mounted = mounted }
        lock.unlock()
    }

    // MARK: volumes

    /// A volume was mounted or unmounted: reads the mount table, re-derives the statuses (a set
    /// whose samples live on a vanished volume turns offline; one whose volume is back turns
    /// ready) and names the sets that must be read again. Nothing is walked.
    @discardableResult
    public func volumesDidChange(mounted now: Set<String>? = nil) -> VolumeChange {
        let mounted = now ?? mountProvider()
        lock.lock()
        let before = _mounted ?? []
        _mounted = mounted
        let sets = _sets, facts = _facts
        lock.unlock()
        var recheck: [String] = []
        for e in sets {
            guard let f = facts[e.path.lowercased()], !f.offline.isEmpty, f.matches(e) else { continue }
            if f.offline.contains(where: { !VolumeState.isOffline($0, mounted: mounted) }) { recheck.append(e.path) }
        }
        rebuildStatuses()
        return VolumeChange(mounted: mounted, appeared: mounted.subtracting(before),
                            disappeared: before.subtracting(mounted), recheck: recheck)
    }

    /// Reads the given sets again (no walk): the lost references that were offline are resolved
    /// against the volumes mounted now. Returns how many sets were read.
    @discardableResult
    public func recheck(setPaths: [String], isCancelled: () -> Bool = { false }) -> Int {
        guard !setPaths.isEmpty else { return 0 }
        writeGate.lock(); defer { writeGate.unlock() }
        lock.lock()
        var sets = _sets, facts = _facts
        let mounted = _mounted ?? mountProvider()
        lock.unlock()
        let env = LiveEnvironment.detect(home: home, applicationsDirs: applicationsDirs)
        let probe = ProbeCache()
        var slot: [String: Int] = [:]
        for (i, e) in sets.enumerated() { slot[e.path.lowercased()] = i }

        var read = 0
        for path in setPaths {
            if isCancelled() { break }
            guard let i = slot[path.lowercased()], let stamp = SetBuilder.stamp(of: sets[i].path) else { continue }
            let old = sets[i]
            let r = SetBuilder.built(path: old.path, stamp: stamp, env: env, probe: probe, mounted: mounted,
                                     isCancelled: isCancelled)
            var fresh = r.entry
            // Derived by the project walks and the inventory, not stored in index.cache.
            fresh.renderNames = old.renderNames; fresh.hasRenders = old.hasRenders
            fresh.projectSize = old.projectSize; fresh.projectFiles = old.projectFiles
            fresh.missingPlugins = old.missingPlugins
            sets[i] = fresh
            let newest = facts[path.lowercased()]?.newestRenderTicks
            if fresh.error.isEmpty, !r.offline.isEmpty || newest != nil || fresh.missingFiles > 0 {
                facts[path.lowercased()] = SetFacts(size: fresh.size, modifiedTicks: DotNetTicks.utc(fresh.modified),
                                                    offline: r.offline, newestRenderTicks: newest)
            } else {
                facts[path.lowercased()] = nil
            }
            read += 1
        }
        guard read > 0, !isCancelled() else { return 0 }

        lock.lock()
        _sets = sets; _facts = facts; _generation += 1
        let projects = _projectFacts
        lock.unlock()
        if IndexCache.save(sets, dir: dir) != .failed { rememberCache(sets) }
        var content = StatusCacheContent()
        content.sets = facts
        content.projects = projects
        StatusCache.save(content, dir: dir)
        refreshInstalled()
        return read
    }
}
