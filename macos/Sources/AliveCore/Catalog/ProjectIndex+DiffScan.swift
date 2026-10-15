// Mac-only: the parts of a scan that belong to the startup diff (see DiffScan.swift): deciding per
// root between a journal replay and a full walk, listing the sets without walking, and recording
// where the journal stood for next time.
import Foundation

extension ProjectIndex {
    /// Key of a root in the plan: standardized and lowercased, like the paths in the caches.
    static func diffKey(_ root: String) -> String { DiffScan.norm(root).lowercased() }

    /// For each enabled root: the folders to read again if the journal can be trusted, nothing if
    /// the root has to be walked in full. Keyed by `diffKey`.
    func planDiff(roots: [String], cache: [String: SetEntry], stats: inout ScanStats,
                  isCancelled: @escaping () -> Bool) -> [String: [String]] {
        let history = ScanHistory.load(dir: dir)
        let stamp = ScanHistory.catalogStamp(dir: dir)
        var plan: [String: [String]] = [:]
        for root in roots {
            if isCancelled() { break }
            let top = DiffScan.norm(root)
            let low = top.lowercased() + "/"
            let underRoot = cache.values.filter { $0.path.lowercased().hasPrefix(low) }
            var mode = DiffScan.mode(history: history[top.lowercased()], identity: historyOps.identity(top),
                                     hasCachedSets: !underRoot.isEmpty, catalogStamp: stamp)
            if case .replay = mode, FolderScan.list(top) == nil { mode = .full(.rootUnreadable) }
            guard case .replay(let since) = mode else {
                if case .full(let why) = mode { fallBack(root, why, &stats) }
                continue
            }
            let projectDirs = Set(underRoot.map { $0.projectDir.lowercased() })
            let outcome = historyOps.replay(top, since, isCancelled)
            if isCancelled() { break }
            switch DiffScan.plan(for: outcome, root: top, projectDirs: projectDirs) {
            case .full(let why): fallBack(root, why, &stats)
            case .regions(let regions):
                plan[Self.diffKey(root)] = regions
                stats.diffRoots += 1
                stats.diffRegions += regions.count
            }
        }
        return plan
    }

    private func fallBack(_ root: String, _ why: FullScanReason, _ stats: inout ScanStats) {
        stats.fullFallbacks.append(why)
        Diag.info("scan: \(root) walked in full (\(why))")
    }

    /// What `collectDiffFiles` found.
    struct DiffCollect {
        var result = FolderScan.Result()
        /// A changed folder could not be (fully) listed and was not confirmed gone.
        var incomplete = false
        /// Lowercased paths of cached rows kept without being able to read the file.
        var kept = Set<String>()
        /// The changed folders that could not be (fully) read; their last project facts stay valid.
        var incompleteRegions: [String] = []
    }

    /// What a diff scan keeps although it could not read it.
    struct DiffKeep {
        var paths = Set<String>()
        var regions: [String] = []
    }

    /// The sets of a root without walking it: the cached ones outside the changed folders (that
    /// still exist), plus whatever a walk of each changed folder finds.
    ///
    /// Only a *confirmed* absence deletes rows: a changed folder that cannot be listed because of
    /// permissions, or because its volume went away during the replay, keeps the rows it had
    /// (and the root is reported `incomplete`, so no checkpoint is recorded for it).
    func collectDiffFiles(root: String, regions: [String], cache: [String: SetEntry],
                          onFile: (String) -> Void, isCancelled: () -> Bool) -> DiffCollect {
        let top = DiffScan.norm(root).lowercased() + "/"
        let covered = regions.map { $0.lowercased() + "/" }
        for e in cache.values {
            if isCancelled() { break }
            let low = e.path.lowercased()
            guard low.hasPrefix(top), !covered.contains(where: { low.hasPrefix($0) }),
                  FileStat.of(e.path) != nil else { continue }
            onFile(e.path)
        }
        var out = DiffCollect()
        for region in regions where !isCancelled() {
            var found = Set<String>()
            let r = FolderScan.find(root: region, ext: ".als", includeBackups: false,
                                    onFile: { found.insert($0.lowercased()); onFile($0) },
                                    isCancelled: isCancelled)
            out.result.dirs += r.dirs
            if r.rootFailed, Self.isConfirmedGone(region, missing: r.rootMissing, mounted: mountProvider()) {
                continue                                        // really deleted: its rows go
            }
            out.result.unreadable += r.unreadable
            guard r.rootFailed || r.unreadable > 0 else { continue }
            // Part of the folder is unknowable right now: what the catalog had there stays.
            out.incomplete = true
            out.incompleteRegions.append(region)
            let inside = region.lowercased() + "/"
            for e in cache.values {
                let low = e.path.lowercased()
                guard low.hasPrefix(inside), !found.contains(low) else { continue }
                if r.rootFailed || FileStat.of(e.path) == nil {
                    out.kept.insert(low)
                    onFile(e.path)
                }
            }
        }
        return out
    }

    /// A folder that cannot be listed is deleted only if it does not exist and its volume is
    /// mounted; a missing folder on an unmounted volume is merely out of reach.
    static func isConfirmedGone(_ path: String, missing: Bool, mounted: Set<String>) -> Bool {
        missing && !VolumeState.isOffline(path, mounted: mounted)
    }

    /// Project folders a diff scan may keep as they were: in a diffed root and not touched.
    func cleanProjects(_ known: [String: ProjectFacts], diffRoots: [String], regions: [String]) -> [String: ProjectFacts] {
        let roots = diffRoots.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var out: [String: ProjectFacts] = [:]
        for (key, facts) in known where roots.contains(where: { key.hasPrefix($0) })
            && DiffScan.isClean(projectDir: key, regions: regions) {
            out[key] = facts
        }
        return out
    }

    /// Remembers where the journal stood when this scan began, for every root that was read
    /// completely. A diffed root keeps the time of its last full walk. A root whose diff was
    /// `incomplete` loses its checkpoint (full walk next time). Call it only once both caches are
    /// saved: the stamp written with each checkpoint is the one of that saved pair.
    func recordHistory(roots: [String], eventId: UInt64, diff: [String: [String]], failed: [String],
                       incomplete: [String] = []) {
        var history = ScanHistory.load(dir: dir)
        let failedKeys = Set(failed.map { $0.lowercased() })
        let incompleteKeys = Set(incomplete.map { $0.lowercased() })
        let stamp = ScanHistory.catalogStamp(dir: dir)
        // Every root keeps (or gets) the stamp of the catalog now on disk, or none at all.
        for root in roots where incompleteKeys.contains(root.lowercased()) {
            history[DiffScan.norm(root).lowercased()] = nil
        }
        for root in roots where !failedKeys.contains(root.lowercased()) && !incompleteKeys.contains(root.lowercased()) {
            let top = DiffScan.norm(root)
            let identity = historyOps.identity(top)
            guard identity.isLocal, identity.isInternal, let uuid = identity.deviceUUID else {
                history[top.lowercased()] = nil
                continue
            }
            let full = diff[Self.diffKey(root)] == nil
            let walkedAt = full ? Date() : (history[top.lowercased()]?.fullWalkAt ?? Date())
            history[top.lowercased()] = RootHistory(path: top, eventId: eventId, deviceUUID: uuid,
                                                    isLocal: true, fullWalkAt: walkedAt, catalogStamp: stamp)
        }
        ScanHistory.save(history, dir: dir)
    }
}
