// Mac-only: regression fixtures for the October 2026 follow-up performance audit.
import CoreServices
import XCTest
@testable import AliveCore

final class CatalogPerformanceAuditTests: XCTestCase {
    private let mounted: Set<String> = ["Macintosh HD"]

    private func index(_ t: TempDir) -> ProjectIndex {
        let idx = ProjectIndex(dir: t.mkdir("data"), home: t.mkdir("home"), applicationsDirs: [])
        idx.inventoryLoader = { _ in PluginInventory() }
        idx.mountProvider = { ["Macintosh HD"] }
        idx.historyOps = ScanHistoryOps(identity: { _ in RootIdentity(deviceUUID: "U", isLocal: true) },
                                         replay: { _, _ in .events([]) }, currentEventId: { 7 })
        return idx
    }

    func testReplayBufferFallsBackInsteadOfKeepingAnUnboundedHistory() {
        let sink = FSEventsReplay.Sink(realRoot: "/real", root: "/shown", maxEvents: 2)
        XCTAssertTrue(sink.add("/real/a", 0))
        XCTAssertTrue(sink.add("/real/b", 0))
        XCTAssertFalse(sink.add("/real/c", 0))
        XCTAssertFalse(sink.add("/real/d", 0))
        XCTAssertEqual(sink.outcome(), .unusable(.tooManyChanges))
        XCTAssertTrue(sink.wait(timeout: 1, isCancelled: { false }))
    }

    func testHistoryMarkerAtTheBufferLimitKeepsTheCompleteEvents() {
        let sink = FSEventsReplay.Sink(realRoot: "/real", root: "/shown", maxEvents: 2)
        sink.add("/real/a", 0)
        sink.add("/real/b", 0)
        sink.add("/real", UInt32(kFSEventStreamEventFlagHistoryDone))
        XCTAssertEqual(sink.outcome(), .events([ReplayedEvent(path: "/shown/a", flags: 0),
                                               ReplayedEvent(path: "/shown/b", flags: 0)]))
    }

    func testDroppedJournalCompletesTheWaitImmediately() {
        let sink = FSEventsReplay.Sink(realRoot: "/r", root: "/r")
        sink.add("/r/a", 0)
        sink.add("/r", UInt32(kFSEventStreamEventFlagUserDropped))
        XCTAssertEqual(sink.outcome(), .unusable(.journalUnreliable))
        XCTAssertTrue(sink.wait(timeout: 1, isCancelled: { false }))
    }

    func testReplayWaitPollsCancellationWithoutWaitingForHistoryOrTimeout() {
        let sink = FSEventsReplay.Sink(realRoot: "/r", root: "/r")
        var polls = 0
        let started = Date()
        XCTAssertFalse(sink.wait(timeout: 20, isCancelled: {
            polls += 1
            return polls >= 3
        }))
        XCTAssertEqual(polls, 3)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "cancelled replay must not wait 20 seconds")
        XCTAssertEqual(FSEventsReplay.events(root: "/unused", since: 0, isCancelled: { true }),
                       .unusable(.replayFailed))
    }

    func testCancelledDiffPlanningSkipsOtherRootsAndWritesNothing() throws {
        let t = makeTemp("cancel-diff")
        t.als("first/A Project/a.als", Fx.simpleSet())
        t.als("second/B Project/b.als", Fx.simpleSet())
        let roots = [t.sub("first"), t.sub("second")]
        let idx = index(t)
        idx.scan(roots: roots)
        let previous = idx.sets
        let files = [IndexCache.path(dir: idx.dir), StatusCache.path(dir: idx.dir), ScanHistory.path(dir: idx.dir)]
        let oldData = try files.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        let cancelled = CancelFlag()
        idx.historyOps.replay = { root, _, isCancelled in
            XCTAssertEqual(root, roots[0], "the second root must never start its replay")
            cancelled.set()
            XCTAssertTrue(isCancelled(), "the scan's flag reaches the replay implementation")
            return .events([])
        }
        let stats = idx.scan(roots: roots, useHistory: true, isCancelled: { cancelled.isSet })
        XCTAssertTrue(stats.cancelled)
        XCTAssertEqual(idx.sets, previous)
        XCTAssertEqual(try files.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }, oldData)
    }

    func testScanDoesNotOverwriteANewerMountNotification() throws {
        let t = makeTemp("scan-mount-race")
        let path = t.als("music/A Project/a.als", Fx.simpleSet())
        let idx = index(t)
        let box = MountBox(mounted.union(["GhostDrive"]))
        idx.mountProvider = { box.value }
        idx.scan(roots: [t.sub("music")])
        var cached = try XCTUnwrap(idx.sets.first)
        cached.samples = ["/Volumes/GhostDrive/kick.wav"]
        cached.sampleSizes = [10]
        XCTAssertEqual(IndexCache.save([cached], dir: idx.dir), .written)
        XCTAssertTrue(idx.loadFromCache(refreshInventory: false))
        let stats = idx.scan(roots: [t.sub("music")], progress: { done, total, _ in
            if done > 0, total > 0 {
                box.value = ["Macintosh HD"]
                idx.volumesDidChange(mounted: box.value)
            }
        })
        XCTAssertFalse(stats.cancelled)
        XCTAssertEqual(stats.reused, 1)
        XCTAssertEqual(idx.statuses[path]?.offlineFiles, 1,
                       "the drive unplugged during parsing must remain offline after publication")
        XCTAssertTrue(idx.volumesDidChange(mounted: box.value).disappeared.isEmpty,
                      "the scan must not restore the old mount table")
    }

    func testAnUnreadableSubfolderRetainsTheFullCatalogAndCheckpoint() throws {
        let t = makeTemp("full-walk-denied")
        t.als("music/A Project/a.als", Fx.simpleSet())
        t.als("music/B Project/b.als", Fx.simpleSet())
        let idx = index(t)
        let root = t.sub("music")
        idx.scan(roots: [root])
        let previous = idx.sets
        let files = [IndexCache.path(dir: idx.dir), StatusCache.path(dir: idx.dir), ScanHistory.path(dir: idx.dir)]
        let oldData = try files.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        let denied = t.sub("music/B Project")
        chmod(denied, 0o000)
        defer { chmod(denied, 0o755) }
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: denied), "permissions are not enforced here")
        t.als("music/A Project/new.als", Fx.simpleSet(tempo: 80))
        idx.historyOps.currentEventId = { 9 }
        let stats = idx.scan(roots: [root])
        XCTAssertEqual(stats.failedRoots, [root])
        XCTAssertTrue(stats.missingRoots.isEmpty)
        XCTAssertTrue(stats.retainedPreviousCatalog)
        XCTAssertEqual(stats.unreadableFolders, 1)
        XCTAssertEqual(idx.sets, previous)
        XCTAssertEqual(try files.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }, oldData)
        chmod(denied, 0o755)
        XCTAssertFalse(idx.scan(roots: [root]).retainedPreviousCatalog)
        XCTAssertEqual(idx.sets.count, 3)
        XCTAssertEqual(ScanHistory.load(dir: idx.dir).values.first?.eventId, 9)
    }

    func testSampleSubfolderFailureKeepsTheRootUntilItCanBeFullyRead() throws {
        let t = makeTemp("samples-partial")
        let root = t.mkdir("Lib")
        t.write("Lib/Pack/kick.wav", "kick")
        t.write("Lib/snare.wav", "snare")
        let previous = SampleIndex.build(roots: [root], disabled: [], mounted: mounted)
        let denied = t.sub("Lib/Pack")
        chmod(denied, 0o000)
        defer { chmod(denied, 0o755) }
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: denied), "permissions are not enforced here")
        t.write("Lib/new.wav", "new")
        let choices: [Set<String>?] = [mounted, nil]
        for volumeKnowledge in choices {
            let kept = SampleIndex.build(roots: [root], disabled: [], previous: previous, mounted: volumeKnowledge)
            XCTAssertEqual(kept.folders, previous.folders)
            XCTAssertEqual(kept.files, previous.files)
        }
        XCTAssertEqual(SampleIndex.countIn(root), -1, "a partial count is unknown")
        chmod(denied, 0o755)
        let recovered = SampleIndex.build(roots: [root], disabled: [], previous: previous, mounted: mounted)
        XCTAssertEqual(recovered.totalSamples, 3)
        try FileManager.default.removeItem(atPath: denied)
        XCTAssertEqual(SampleIndex.build(roots: [root], disabled: [], previous: recovered,
                                         mounted: mounted).totalSamples, 2, "confirmed deletion still removes samples")
    }

    func testSampleWalkCanCancelInsideOneWideDirectory() {
        let t = makeTemp("wide-samples")
        for i in 0..<600 { t.write("Lib/s\(i).wav") }
        var polls = 0
        let result = SampleIndex.walk(root: t.sub("Lib"), known: nil, found: { _ in }, isCancelled: {
            polls += 1
            return polls > 2
        })
        XCTAssertNil(result)
        XCTAssertEqual(polls, 3)
    }
}
