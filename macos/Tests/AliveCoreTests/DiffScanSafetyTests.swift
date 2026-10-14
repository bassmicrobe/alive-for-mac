import CoreServices
import XCTest
@testable import AliveCore

/// The journal checkpoint is only advanced when the catalog it belongs to is on disk, an unreadable
/// changed folder keeps its rows, and only internal volumes are replayed.
final class DiffScanSafetyTests: XCTestCase {
    private final class Journal: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: ReplayOutcome = .events([])
        private var _id: UInt64 = 7
        var events: ReplayOutcome {
            get { lock.lock(); defer { lock.unlock() }; return _events }
            set { lock.lock(); _events = newValue; lock.unlock() }
        }
        var currentId: UInt64 {
            get { lock.lock(); defer { lock.unlock() }; return _id }
            set { lock.lock(); _id = newValue; lock.unlock() }
        }
    }

    private func makeIndex(_ t: TempDir, journal: Journal, isInternal: Bool = true) -> ProjectIndex {
        let index = ProjectIndex(dir: t.sub("data"), home: t.mkdir("home"), applicationsDirs: [], settings: Settings())
        index.mountProvider = { ["Macintosh HD"] }
        index.historyOps = ScanHistoryOps(
            identity: { _ in RootIdentity(deviceUUID: "U", isLocal: true, isInternal: isInternal) },
            replay: { _, _ in journal.events }, currentEventId: { journal.currentId })
        return index
    }

    private func library(_ t: TempDir) -> String {
        for name in ["A", "B", "C"] {
            t.als("music/\(name) Project/\(name).als", Fx.simpleSet())
            t.write("music/\(name) Project/Samples/x.wav", "12345")
        }
        return t.sub("music")
    }

    private let created = Int(kFSEventStreamEventFlagItemIsFile | kFSEventStreamEventFlagItemCreated)

    // MARK: 4 — checkpoint only after the caches are saved

    func testFailedCacheSaveDoesNotAdvanceTheCheckpoint() throws {
        let t = makeTemp("diff-order")
        let root = library(t)
        let journal = Journal()
        let first = makeIndex(t, journal: journal)
        first.scan(roots: [root])
        XCTAssertEqual(ScanHistory.load(dir: t.sub("data")).values.first?.eventId, 7)

        // index.cache can no longer be replaced: a directory sits where the file was.
        let cache = IndexCache.path(dir: t.sub("data"))
        try FileManager.default.removeItem(atPath: cache)
        try FileManager.default.createDirectory(atPath: cache + "/keep", withIntermediateDirectories: true)

        t.als("music/C Project/C2.als", Fx.simpleSet(tempo: 99))
        journal.currentId = 9
        journal.events = .events([ReplayedEvent(path: t.sub("music/C Project/C2.als"), flags: UInt32(created))])
        let stats = first.scan(roots: [root], useHistory: false)

        XCTAssertTrue(stats.checkpointKept)
        XCTAssertEqual(ScanHistory.load(dir: t.sub("data")).values.first?.eventId, 7,
                       "the checkpoint stays with the catalog it was taken with")
    }

    func testCheckpointCarriesTheStampOfTheSavedPair() throws {
        let t = makeTemp("diff-stamp")
        let root = library(t)
        let journal = Journal()
        makeIndex(t, journal: journal).scan(roots: [root])
        let stored = try XCTUnwrap(ScanHistory.load(dir: t.sub("data")).values.first)
        XCTAssertEqual(stored.catalogStamp, ScanHistory.catalogStamp(dir: t.sub("data")))
        XCTAssertFalse(stored.catalogStamp.contains("-|") || stored.catalogStamp.hasPrefix("-"))
    }

    func testAMismatchedCatalogForcesAFullScan() throws {
        let t = makeTemp("diff-mismatch")
        let root = library(t)
        let journal = Journal()
        makeIndex(t, journal: journal).scan(roots: [root])

        // index.cache changes behind the checkpoint's back (an older/newer copy, a half write).
        t.setModified(IndexCache.path(dir: t.sub("data")), Date().addingTimeInterval(-3600))
        let index = makeIndex(t, journal: journal)
        XCTAssertTrue(index.loadFromCache(refreshInventory: false))
        XCTAssertEqual(index.scan(roots: [root], useHistory: true).fullFallbacks, [.catalogMismatch])
    }

    func testAHistoryFileWithoutAStampIsNotTrusted() throws {
        let t = makeTemp("diff-oldfile")
        let root = library(t)
        let journal = Journal()
        makeIndex(t, journal: journal).scan(roots: [root])
        var history = ScanHistory.load(dir: t.sub("data"))
        for key in history.keys { history[key]?.catalogStamp = "" }
        ScanHistory.save(history, dir: t.sub("data"))
        // Written by an older build: five fields only.
        let line = try XCTUnwrap(String(contentsOfFile: ScanHistory.path(dir: t.sub("data")), encoding: .utf8)
            .split(separator: "\n").first)
        let five = line.split(separator: "\t", omittingEmptySubsequences: false).dropLast().joined(separator: "\t")
        t.write("data/scan-history.cfg", five + "\n")
        XCTAssertEqual(ScanHistory.load(dir: t.sub("data")).count, 1)

        let index = makeIndex(t, journal: journal)
        XCTAssertTrue(index.loadFromCache(refreshInventory: false))
        XCTAssertEqual(index.scan(roots: [root], useHistory: true).fullFallbacks, [.catalogMismatch])
    }

    // MARK: 5 — unreadable regions keep their rows

    func testUnreadableChangedFolderKeepsItsRowsAndForgetsTheCheckpoint() throws {
        let t = makeTemp("diff-unreadable")
        let root = library(t)
        let journal = Journal()
        makeIndex(t, journal: journal).scan(roots: [root])
        XCTAssertEqual(ScanHistory.load(dir: t.sub("data")).count, 1)

        let locked = t.sub("music/B Project")
        journal.events = .events([ReplayedEvent(path: locked + "/B.als", flags: UInt32(created))])
        chmod(locked, 0o000)
        defer { chmod(locked, 0o755) }
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: locked), "permissions are not enforced here")

        let index = makeIndex(t, journal: journal)
        XCTAssertTrue(index.loadFromCache(refreshInventory: false))
        let stats = index.scan(roots: [root], useHistory: true)

        XCTAssertEqual(stats.diffRoots, 1)
        XCTAssertEqual(stats.incompleteDiffRoots, [root])
        XCTAssertEqual(index.sets.map(\.name).sorted(), ["A", "B", "C"], "B was not read, so it was not deleted")
        XCTAssertTrue(ScanHistory.load(dir: t.sub("data")).isEmpty, "next launch walks in full")
        // And that next launch really is a full one.
        chmod(locked, 0o755)
        let next = makeIndex(t, journal: journal)
        XCTAssertTrue(next.loadFromCache(refreshInventory: false))
        XCTAssertEqual(next.scan(roots: [root], useHistory: true).fullFallbacks, [.noHistory])
    }

    func testOnlyAConfirmedAbsenceDeletes() {
        XCTAssertTrue(ProjectIndex.isConfirmedGone("/music/B", missing: true, mounted: ["Macintosh HD"]))
        XCTAssertFalse(ProjectIndex.isConfirmedGone("/music/B", missing: false, mounted: ["Macintosh HD"]),
                       "exists but cannot be listed")
        XCTAssertFalse(ProjectIndex.isConfirmedGone("/Volumes/Ghost/B", missing: true, mounted: ["Macintosh HD"]),
                       "its volume is gone: out of reach, not deleted")
        XCTAssertTrue(ProjectIndex.isConfirmedGone("/Volumes/Ghost/B", missing: true, mounted: ["Ghost"]))
    }

    func testDeletedFolderStillDeletesItsRows() throws {
        let t = makeTemp("diff-deleted")
        let root = library(t)
        let journal = Journal()
        makeIndex(t, journal: journal).scan(roots: [root])
        try FileManager.default.removeItem(atPath: t.sub("music/B Project"))
        journal.events = .events([ReplayedEvent(path: t.sub("music/B Project"),
                                                flags: UInt32(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemRemoved))])
        let index = makeIndex(t, journal: journal)
        XCTAssertTrue(index.loadFromCache(refreshInventory: false))
        let stats = index.scan(roots: [root], useHistory: true)
        XCTAssertTrue(stats.incompleteDiffRoots.isEmpty)
        XCTAssertEqual(index.sets.map(\.name).sorted(), ["A", "C"])
    }

    // MARK: 6 — only internal volumes use the journal

    func testExternalVolumesAreAlwaysWalkedInFull() {
        let history = RootHistory(path: "/r", eventId: 1, deviceUUID: "U", isLocal: true, fullWalkAt: Date())
        let external = RootIdentity(deviceUUID: "U", isLocal: true, isInternal: false)
        XCTAssertEqual(DiffScan.mode(history: history, identity: external, hasCachedSets: true), .full(.externalVolume))
        let internalDisk = RootIdentity(deviceUUID: "U", isLocal: true, isInternal: true)
        XCTAssertEqual(DiffScan.mode(history: history, identity: internalDisk, hasCachedSets: true), .replay(since: 1))
    }

    func testNoCheckpointIsRecordedForAnExternalVolume() {
        let t = makeTemp("diff-external")
        let root = library(t)
        let journal = Journal()
        makeIndex(t, journal: journal, isInternal: false).scan(roots: [root])
        XCTAssertTrue(ScanHistory.load(dir: t.sub("data")).isEmpty)
    }
}
