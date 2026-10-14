import XCTest
@testable import AliveCore

/// Offline vs missing during a scan, the status.cache sidecar, and volumes coming and going.
final class SetStatusScanTests: XCTestCase {
    private let base: Set<String> = ["Macintosh HD"]
    private let ghost = "/Volumes/GhostDrive/packs/kick.wav"
    private let gone = "/Users/nobody-here/sounds/gone.wav"

    private struct Lib {
        let t: TempDir
        let root: String
        let data: String
        let index: ProjectIndex
    }

    private func makeLib(mounted: @escaping @Sendable () -> Set<String>) -> Lib {
        let t = makeTemp("status")
        let root = t.mkdir("music")
        let data = t.mkdir("data")
        let index = ProjectIndex(dir: data, home: t.mkdir("home"), applicationsDirs: [], settings: Settings())
        index.mountProvider = mounted
        index.historyOps = ScanHistoryOps(identity: { _ in RootIdentity(deviceUUID: nil, isLocal: false) },
                                          replay: { _, _ in .unusable(.replayFailed) }, currentEventId: { 1 })
        return Lib(t: t, root: root, data: data, index: index)
    }

    private func setXML(_ paths: [String]) -> String {
        Fx.simpleSet(extra: paths.map { Fx.fileRef(rel: "", abs: $0, type: 0) }.joined())
    }

    func testLostReferencesAreOfflineOnlyWhenTheirVolumeIsGone() {
        let lib = makeLib { self.base }
        lib.t.als("music/A Project/A.als", setXML([ghost, gone]))
        lib.index.scan(roots: [lib.root])

        let set = try! XCTUnwrap(lib.index.sets.first)
        XCTAssertEqual(set.missingFiles, 2, "upstream's count keeps both")
        let status = try! XCTUnwrap(lib.index.statuses[set.path])
        XCTAssertEqual(status.offlineFiles, 1)
        XCTAssertEqual(status.offlineVolumes, ["GhostDrive"])
        XCTAssertEqual(status.missingFiles, 1)
        XCTAssertEqual(status.readiness, .missingFiles)
        XCTAssertEqual(lib.index.offlineReferences()[set.path], [ghost])
    }

    func testOnlyOfflineReferencesMakeAnOfflineSet() {
        let lib = makeLib { self.base }
        lib.t.als("music/B Project/B.als", setXML([ghost]))
        lib.index.scan(roots: [lib.root])
        let status = try! XCTUnwrap(lib.index.statuses[lib.index.sets[0].path])
        XCTAssertEqual(status.missingFiles, 0)
        XCTAssertEqual(status.offlineFiles, 1)
        // Plugin inventory unavailable in the test environment's home: unknown beats ready.
        XCTAssertNotEqual(status.readiness, .ready)
    }

    func testSidecarRoundTripAndWriteOnlyWhenChanged() throws {
        let lib = makeLib { self.base }
        lib.t.als("music/A Project/A.als", setXML([ghost, gone]))
        lib.t.write("music/A Project/Render/mix.wav")
        lib.index.scan(roots: [lib.root])

        let path = StatusCache.path(dir: lib.data)
        let first = try XCTUnwrap(FileStat.of(path))
        let content = StatusCache.load(dir: lib.data)
        XCTAssertEqual(content.sets.count, 1)
        XCTAssertEqual(content.sets.values.first?.offline, [ghost])
        XCTAssertNotNil(content.sets.values.first?.newestRender)
        XCTAssertEqual(content.projects.values.first?.renders, ["mix"])

        lib.index.scan(roots: [lib.root])      // nothing changed: the file is not rewritten
        let second = try XCTUnwrap(FileStat.of(path))
        XCTAssertEqual(first.modified, second.modified)

        // A new process reads the same statuses from the caches alone.
        let again = ProjectIndex(dir: lib.data, home: lib.t.sub("home"), applicationsDirs: [], settings: Settings())
        again.mountProvider = { self.base }
        XCTAssertTrue(again.loadFromCache(refreshInventory: false))
        let set = again.sets[0]
        XCTAssertEqual(again.statuses[set.path]?.offlineFiles, 1)
        XCTAssertEqual(again.statuses[set.path]?.missingFiles, 1)
        XCTAssertNotNil(again.statuses[set.path]?.newestRender)
    }

    func testSidecarFactsAreDroppedWhenTheSetChanges() throws {
        let lib = makeLib { self.base }
        let als = lib.t.als("music/A Project/A.als", setXML([ghost]))
        lib.index.scan(roots: [lib.root])
        var facts = try XCTUnwrap(StatusCache.load(dir: lib.data).sets.values.first)
        let entry = lib.index.sets[0]
        XCTAssertTrue(facts.matches(entry))
        lib.t.setModified(als, Date().addingTimeInterval(-5))
        var changed = entry
        changed.modified = Date().addingTimeInterval(-5)
        XCTAssertFalse(facts.matches(changed))
        facts.size += 1
        XCTAssertFalse(facts.matches(entry))
    }

    func testDamagedSidecarReadsAsEmpty() throws {
        let lib = makeLib { self.base }
        lib.t.write("data/status.cache", "{ not json")
        XCTAssertEqual(StatusCache.load(dir: lib.data), StatusCacheContent())
    }

    func testMountAndUnmountTransitions() {
        let mounted = MountBox(base)
        let lib = makeLib { mounted.value }
        lib.t.als("music/A Project/A.als", setXML([ghost]))
        lib.index.scan(roots: [lib.root])
        let path = lib.index.sets[0].path
        XCTAssertEqual(lib.index.statuses[path]?.offlineFiles, 1)

        // The drive appears: the set has to be read again, and now its file is simply not there.
        mounted.value = base.union(["GhostDrive"])
        let change = lib.index.volumesDidChange()
        XCTAssertEqual(change.appeared, ["GhostDrive"])
        XCTAssertEqual(change.recheck, [path])
        XCTAssertEqual(lib.index.recheck(setPaths: change.recheck), 1)
        XCTAssertEqual(lib.index.statuses[path]?.offlineFiles, 0)
        XCTAssertEqual(lib.index.statuses[path]?.missingFiles, 1)
        XCTAssertEqual(lib.index.volumesDidChange(mounted: mounted.value).recheck, [])

        // And goes away again: references that were really lost stay lost, nothing is re-read.
        mounted.value = base
        let gone = lib.index.volumesDidChange()
        XCTAssertEqual(gone.disappeared, ["GhostDrive"])
        XCTAssertTrue(gone.recheck.isEmpty)
        XCTAssertEqual(lib.index.statuses[path]?.missingFiles, 1)
    }

    func testFoundSamplesTurnOfflineWhenTheirVolumeIsUnmounted() {
        var entry = SetEntry()
        entry.path = "/x/A Project/A.als"
        entry.samples = ["/Volumes/GhostDrive/a.wav", "/Volumes/GhostDrive/b.wav", "/Volumes/Other/c.wav", "/Users/me/d.wav"]
        entry.missingPlugins = 0
        let up = SetStatus.derive(entry: entry, offlinePaths: [], newestRender: nil,
                                  mounted: ["GhostDrive", "Other"], pluginsKnown: true)
        XCTAssertEqual(up.offlineFiles, 0)
        XCTAssertEqual(up.readiness, .ready)
        let down = SetStatus.derive(entry: entry, offlinePaths: [], newestRender: nil,
                                    mounted: ["Other"], pluginsKnown: true)
        XCTAssertEqual(down.offlineFiles, 2)
        XCTAssertEqual(down.offlineVolumes, ["GhostDrive"])
        XCTAssertEqual(down.readiness, .offline)
    }

    func testPluginsAreUnknownNotMissingWhenTheInventoryIsUnavailable() {
        var entry = SetEntry()
        entry.missingPlugins = 3
        let s = SetStatus.derive(entry: entry, offlinePaths: [], newestRender: nil, mounted: [], pluginsKnown: false)
        XCTAssertNil(s.missingPlugins)
        XCTAssertEqual(s.readiness, .unknown)
    }

    func testStaleRenderComesFromTheNewestRender() throws {
        let lib = makeLib { self.base }
        let als = lib.t.als("music/A Project/A.als", Fx.simpleSet())
        let render = lib.t.write("music/A Project/Render/mix.wav")
        lib.t.setModified(als, Date())
        lib.t.setModified(render, Date().addingTimeInterval(-3600))
        lib.index.scan(roots: [lib.root])
        XCTAssertEqual(lib.index.statuses[lib.index.sets[0].path]?.renderIsStale, true)
        lib.t.setModified(render, Date().addingTimeInterval(60))
        lib.index.scan(roots: [lib.root])
        XCTAssertEqual(lib.index.statuses[lib.index.sets[0].path]?.renderIsStale, false)
    }

    // MARK: reuse rules

    func testCachedSetIsReadAgainWhenItsOfflineVolumeIsBack() {
        let mounted = MountBox(base)
        let lib = makeLib { mounted.value }
        lib.t.als("music/A Project/A.als", setXML([ghost]))
        lib.t.als("music/B Project/B.als", Fx.simpleSet())
        XCTAssertEqual(lib.index.scan(roots: [lib.root]).parsed, 2)
        XCTAssertEqual(lib.index.scan(roots: [lib.root]).parsed, 0, "volume still gone: nothing to redo")
        mounted.value = base.union(["GhostDrive"])
        let stats = lib.index.scan(roots: [lib.root])
        XCTAssertEqual(stats.parsed, 1)
        XCTAssertEqual(stats.reused, 1)
    }

    func testCacheWrittenBeforeTheSidecarIsReadOnceForSetsWithLostFiles() {
        let lib = makeLib { self.base }
        lib.t.als("music/A Project/A.als", setXML([ghost, gone]))
        lib.t.als("music/B Project/B.als", Fx.simpleSet())
        lib.index.scan(roots: [lib.root])
        try? FileManager.default.removeItem(atPath: StatusCache.path(dir: lib.data))

        let fresh = ProjectIndex(dir: lib.data, home: lib.t.sub("home"), applicationsDirs: [], settings: Settings())
        fresh.mountProvider = { self.base }
        let first = fresh.scan(roots: [lib.root])
        XCTAssertEqual(first.parsed, 1, "only the set with lost references is re-read")
        XCTAssertEqual(fresh.scan(roots: [lib.root]).parsed, 0)
    }
}

final class MountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var set: Set<String>
    init(_ set: Set<String>) { self.set = set }
    var value: Set<String> {
        get { lock.lock(); defer { lock.unlock() }; return set }
        set { lock.lock(); set = newValue; lock.unlock() }
    }
}
