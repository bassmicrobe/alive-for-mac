// Mac-only: the parts of a scan that belong to the startup diff (see DiffScan.swift): deciding per
// root between a journal replay and a full walk, listing the sets without walking, and recording
// where the journal stood for next time.
import Foundation

extension ProjectIndex {
    /// Key of a root in the plan: standardized and lowercased, like the paths in the caches.
    static func diffKey(_ root: String) -> String { DiffScan.norm(root).lowercased() }

    /// For each enabled root: the folders to read again if the journal can be trusted, nothing if
    /// the root has to be walked in full. Keyed by `diffKey`.
    func planDiff(roots: [String], cache: [String: SetEntry], stats: inout ScanStats) -> [String: [String]] {
        let history = ScanHistory.load(dir: dir)
        var plan: [String: [String]] = [:]
        for root in roots {
            let top = DiffScan.norm(root)
            let low = top.lowercased() + "/"
            let underRoot = cache.values.filter { $0.path.lowercased().hasPrefix(low) }
            var mode = DiffScan.mode(history: history[top.lowercased()], identity: historyOps.identity(top),
                                     hasCachedSets: !underRoot.isEmpty)
            if case .replay = mode, FolderScan.list(top) == nil { mode = .full(.rootUnreadable) }
            guard case .replay(let since) = mode else {
                if case .full(let why) = mode { fallBack(root, why, &stats) }
                continue
            }
            let projectDirs = Set(underRoot.map { $0.projectDir.lowercased() })
            switch DiffScan.plan(for: historyOps.replay(top, since), root: top, projectDirs: projectDirs) {
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

    /// The sets of a root without walking it: the cached ones outside the changed folders (that
    /// still exist), plus whatever a walk of each changed folder finds.
    func collectDiffFiles(root: String, regions: [String], cache: [String: SetEntry],
                          onFile: (String) -> Void, isCancelled: () -> Bool) -> FolderScan.Result {
        let top = DiffScan.norm(root).lowercased() + "/"
        let covered = regions.map { $0.lowercased() + "/" }
        for e in cache.values {
            if isCancelled() { break }
            let low = e.path.lowercased()
            guard low.hasPrefix(top), !covered.contains(where: { low.hasPrefix($0) }),
                  FileStat.of(e.path) != nil else { continue }
            onFile(e.path)
        }
        var total = FolderScan.Result()
        for region in regions where !isCancelled() {
            let r = FolderScan.find(root: region, ext: ".als", includeBackups: false, onFile: onFile,
                                    isCancelled: isCancelled)
            total.dirs += r.dirs
            total.unreadable += r.rootFailed ? 0 : r.unreadable    // a vanished folder is a deletion, not damage
        }
        return total
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
    /// completely. A diffed root keeps the time of its last full walk.
    func recordHistory(roots: [String], eventId: UInt64, diff: [String: [String]], failed: [String]) {
        var history = ScanHistory.load(dir: dir)
        let failedKeys = Set(failed.map { $0.lowercased() })
        for root in roots where !failedKeys.contains(root.lowercased()) {
            let top = DiffScan.norm(root)
            let identity = historyOps.identity(top)
            guard identity.isLocal, let uuid = identity.deviceUUID else {
                history[top.lowercased()] = nil
                continue
            }
            let full = diff[Self.diffKey(root)] == nil
            let walkedAt = full ? Date() : (history[top.lowercased()]?.fullWalkAt ?? Date())
            history[top.lowercased()] = RootHistory(path: top, eventId: eventId, deviceUUID: uuid,
                                                    isLocal: true, fullWalkAt: walkedAt)
        }
        ScanHistory.save(history, dir: dir)
    }
}
