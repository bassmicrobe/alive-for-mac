import CoreServices
import XCTest
@testable import AliveCore

/// The startup diff scan: when to trust the event journal, what its events mean, and a scan that
/// uses it (with the journal stubbed so no real FSEvents history is needed).
final class DiffScanDecisionTests: XCTestCase {
    private let now = Date()
    private func history(id: UInt64 = 42, uuid: String = "U", local: Bool = true,
                         walked: Date? = nil) -> RootHistory {
        RootHistory(path: "/r", eventId: id, deviceUUID: uuid, isLocal: local, fullWalkAt: walked ?? now)
    }
    private let local = RootIdentity(deviceUUID: "U", isLocal: true)

    func testReplaysOnlyWhenEverythingIsTrustworthy() {
        XCTAssertEqual(DiffScan.mode(history: history(), identity: local, hasCachedSets: true, now: now),
                       .replay(since: 42))
    }

    func testFallsBackToFullWalks() {
        func mode(_ h: RootHistory?, _ id: RootIdentity, cached: Bool = true, at: Date? = nil) -> RootScanMode {
            DiffScan.mode(history: h, identity: id, hasCachedSets: cached, now: at ?? now)
        }
        XCTAssertEqual(mode(nil, local), .full(.noHistory))
        XCTAssertEqual(mode(history(uuid: "OTHER"), local), .full(.deviceChanged))
        XCTAssertEqual(mode(history(), RootIdentity(deviceUUID: "U", isLocal: false)), .full(.notLocal))
        XCTAssertEqual(mode(history(local: false), local), .full(.notLocal))
        XCTAssertEqual(mode(history(), RootIdentity(deviceUUID: nil, isLocal: true)), .full(.noJournal))
        XCTAssertEqual(mode(history(), local, cached: false), .full(.noCachedSets))
        XCTAssertEqual(mode(history(), local, at: now.addingTimeInterval(DiffScan.maxHistoryAge + 60)),
                       .full(.tooOld))
    }

    private func event(_ path: String, _ flags: Int) -> ReplayedEvent {
        ReplayedEvent(path: path, flags: UInt32(flags))
    }
    private let file = kFSEventStreamEventFlagItemIsFile | kFSEventStreamEventFlagItemModified
    private let dirMade = kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemCreated

    func testEventsBecomeTheProjectFoldersTheyBelongTo() {
        let known: Set<String> = ["/r/a project", "/r/b project"]
        let plan = DiffScan.plan(for: .events([
            event("/r/A Project/A.als", file),
            event("/r/A Project/Samples/rec.wav", file),                     // same project: one region
            event("/r/B Project/Render/mix.wav", file),
            event("/r/A Project/.DS_Store", file),                           // hidden: ignored
            event("/r/C Project", dirMade),                                  // a new project folder
            event("/r/C Project/C.als", file),
            event("/r/Misc/loose.als", file),                                // new ground outside any project
        ]), root: "/r", projectDirs: known)
        XCTAssertEqual(plan, .regions(["/r/A Project", "/r/B Project", "/r/C Project", "/r/Misc"]))
    }

    func testQuietJournalMeansNothingToRead() {
        XCTAssertEqual(DiffScan.plan(for: .events([event("/r", kFSEventStreamEventFlagHistoryDone)]),
                                     root: "/r", projectDirs: []), .regions([]))
    }

    func testUnreliableJournalMeansAFullWalk() {
        for flag in [kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagRootChanged,
                     kFSEventStreamEventFlagUserDropped, kFSEventStreamEventFlagKernelDropped] {
            XCTAssertEqual(DiffScan.plan(for: .events([event("/r/x", flag)]), root: "/r", projectDirs: []),
                           .full(.journalUnreliable))
        }
        XCTAssertEqual(DiffScan.plan(for: .unusable(.replayFailed), root: "/r", projectDirs: []),
                       .full(.replayFailed))
    }

    func testEventsAboutTheRootItselfAreIgnoredUnlessItIsGone() {
        let attrs = Int(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemXattrMod)
        XCTAssertEqual(DiffScan.plan(for: .events([event("/r", attrs)]), root: "/r", projectDirs: []), .regions([]))
        let gone = Int(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemRemoved)
        XCTAssertEqual(DiffScan.plan(for: .events([event("/r", gone)]), root: "/r", projectDirs: []),
                       .full(.changedAtRoot))
    }

    func testChangeDirectlyInTheRootMeansAFullWalk() {
        XCTAssertEqual(DiffScan.plan(for: .events([event("/r/new.als", file)]), root: "/r", projectDirs: []),
                       .full(.changedAtRoot))
    }

    func testTooManyRegionsMeansAFullWalk() {
        let events = (0...DiffScan.maxRegions).map { event("/r/p\($0)/x.als", file) }
        XCTAssertEqual(DiffScan.plan(for: .events(events), root: "/r", projectDirs: []), .full(.tooManyChanges))
    }

    func testCleanProjectsAreTheOnesNoRegionTouches() {
        XCTAssertTrue(DiffScan.isClean(projectDir: "/r/b project", regions: ["/r/a project"]))
        XCTAssertFalse(DiffScan.isClean(projectDir: "/r/a project", regions: ["/r/a project"]))
        XCTAssertFalse(DiffScan.isClean(projectDir: "/r/a project", regions: ["/r/a project/sub"]))
        XCTAssertFalse(DiffScan.isClean(projectDir: "/r/a project/x", regions: ["/r/a project"]))
        XCTAssertTrue(DiffScan.isClean(projectDir: "/r/ab project", regions: ["/r/a"]))
    }

    func testHistoryRoundTrip() throws {
        let t = makeTemp("hist")
        let h = history(id: 123_456_789_012)
        ScanHistory.save(["/r": h], dir: t.path)
        let back = ScanHistory.load(dir: t.path)
        XCTAssertEqual(back["/r"]?.eventId, 123_456_789_012)
        XCTAssertEqual(back["/r"]?.deviceUUID, "U")
        XCTAssertEqual(back["/r"]?.isLocal, true)
        t.write("scan-history.cfg", "garbage\n/r\tnot-a-number\tU\t1\t5\n")
        XCTAssertTrue(ScanHistory.load(dir: t.path).isEmpty)
    }
}

final class DiffScanIndexTests: XCTestCase {
    private final class Journal: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: ReplayOutcome = .events([])
        private var _replays = 0
        var events: ReplayOutcome {
            get { lock.lock(); defer { lock.unlock() }; return _events }
            set { lock.lock(); _events = newValue; lock.unlock() }
        }
        var replays: Int { lock.lock(); defer { lock.unlock() }; return _replays }
        func replayed() -> ReplayOutcome { lock.lock(); _replays += 1; let e = _events; lock.unlock(); return e }
    }

    private func makeIndex(_ t: TempDir, journal: Journal, local: Bool = true) -> ProjectIndex {
        let index = ProjectIndex(dir: t.sub("data"), home: t.mkdir("home"), applicationsDirs: [], settings: Settings())
        index.mountProvider = { ["Macintosh HD"] }
        index.historyOps = ScanHistoryOps(identity: { _ in RootIdentity(deviceUUID: "U", isLocal: local) },
                                          replay: { _, _ in journal.replayed() }, currentEventId: { 7 })
        return index
    }

    private func library(_ t: TempDir) -> String {
        for name in ["A", "B", "C"] {
            t.als("music/\(name) Project/\(name).als", Fx.simpleSet())
            t.write("music/\(name) Project/Samples/x.wav", "12345")
        }
        t.write("music/B Project/Render/mix.wav")
        return t.sub("music")
    }

    func testLaunchScanReadsOnlyWhatTheJournalNames() throws {
        let t = makeTemp("diff")
        let root = library(t)
        let journal = Journal()
        let index = makeIndex(t, journal: journal)

        // The first launch has no history: a full walk, which leaves one behind.
        var stats = index.scan(roots: [root], useHistory: true)
        XCTAssertEqual(stats.diffRoots, 0)
        XCTAssertEqual(stats.fullFallbacks, [.noHistory])
        XCTAssertEqual(journal.replays, 0)
        XCTAssertEqual(ScanHistory.load(dir: t.sub("data")).values.first?.eventId, 7)

        // Changes the journal knows about: C gains a set and B gets a new render. Changes it does
        // not know about (a file dropped into A's Samples) must NOT be seen: A is not walked.
        t.als("music/C Project/C2.als", Fx.simpleSet(tempo: 99))
        t.write("music/B Project/Render/final.wav")
        t.write("music/A Project/Samples/silent.wav", String(repeating: "z", count: 5000))
        let sizeA = try XCTUnwrap(index.sets.first { $0.name == "A" }).projectSize
        let flags = Int(kFSEventStreamEventFlagItemIsFile | kFSEventStreamEventFlagItemCreated)
        journal.events = .events([
            ReplayedEvent(path: t.sub("music/C Project/C2.als"), flags: UInt32(flags)),
            ReplayedEvent(path: t.sub("music/B Project/Render/final.wav"), flags: UInt32(flags)),
        ])
        let again = ProjectIndex(dir: t.sub("data"), home: t.sub("home"), applicationsDirs: [], settings: Settings())
        again.mountProvider = { ["Macintosh HD"] }
        again.historyOps = index.historyOps
        XCTAssertTrue(again.loadFromCache(refreshInventory: false))
        stats = again.scan(roots: [root], useHistory: true)

        XCTAssertEqual(stats.diffRoots, 1)
        XCTAssertEqual(stats.diffRegions, 2)
        XCTAssertEqual(journal.replays, 1)
        XCTAssertEqual(again.sets.count, 4)
        XCTAssertEqual(stats.parsed, 1)                       // only the new C2.als
        let a = try XCTUnwrap(again.sets.first { $0.name == "A" })
        XCTAssertEqual(a.projectSize, sizeA, "A was not walked: the silent file is not in its weight")
        let b = try XCTUnwrap(again.sets.first { $0.name == "B" })
        XCTAssertEqual(Set(b.renderNames), ["mix", "final"])
        XCTAssertTrue(b.hasRenders)
    }

    func testAJournalThatCannotBeTrustedFallsBackToTheFullWalk() throws {
        let t = makeTemp("diff")
        let root = library(t)
        let journal = Journal()
        makeIndex(t, journal: journal).scan(roots: [root])
        t.write("music/A Project/Samples/silent.wav", String(repeating: "z", count: 5000))

        journal.events = .events([ReplayedEvent(path: root, flags: UInt32(kFSEventStreamEventFlagMustScanSubDirs))])
        let index = makeIndex(t, journal: journal)
        XCTAssertTrue(index.loadFromCache(refreshInventory: false))
        let stats = index.scan(roots: [root], useHistory: true)
        XCTAssertEqual(stats.diffRoots, 0)
        XCTAssertEqual(stats.fullFallbacks, [.journalUnreliable])
        let a = try XCTUnwrap(index.sets.first { $0.name == "A" })
        XCTAssertEqual(a.projectSize, 5 + 5000 + Int64(FileStat.of(t.sub("music/A Project/A.als"))!.size))
    }

    func testNetworkRootsAreAlwaysWalkedInFull() {
        let t = makeTemp("diff")
        let root = library(t)
        let journal = Journal()
        makeIndex(t, journal: journal, local: false).scan(roots: [root])
        let index = makeIndex(t, journal: journal, local: false)
        let stats = index.scan(roots: [root], useHistory: true)
        XCTAssertEqual(stats.fullFallbacks, [.noHistory])      // never recorded for a non-local root
        XCTAssertEqual(journal.replays, 0)
        XCTAssertTrue(ScanHistory.load(dir: t.sub("data")).isEmpty)
    }

    func testAChangedDeviceMeansAFullWalk() {
        let t = makeTemp("diff")
        let root = library(t)
        let journal = Journal()
        makeIndex(t, journal: journal).scan(roots: [root])
        let index = makeIndex(t, journal: journal)
        index.historyOps.identity = { _ in RootIdentity(deviceUUID: "ANOTHER", isLocal: true) }
        XCTAssertEqual(index.scan(roots: [root], useHistory: true).fullFallbacks, [.deviceChanged])
    }

    func testManualRescanNeverUsesTheJournal() {
        let t = makeTemp("diff")
        let root = library(t)
        let journal = Journal()
        let index = makeIndex(t, journal: journal)
        index.scan(roots: [root])
        let stats = index.scan(roots: [root])
        XCTAssertEqual(stats.diffRoots, 0)
        XCTAssertEqual(journal.replays, 0)
    }

    func testDeletedProjectDisappearsAndNoSetIsInvented() throws {
        let t = makeTemp("diff")
        let root = library(t)
        let journal = Journal()
        makeIndex(t, journal: journal).scan(roots: [root])
        try FileManager.default.removeItem(atPath: t.sub("music/B Project"))
        journal.events = .events([ReplayedEvent(path: t.sub("music/B Project"),
                                                flags: UInt32(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemRemoved))])
        let index = makeIndex(t, journal: journal)
        XCTAssertTrue(index.loadFromCache(refreshInventory: false))
        let stats = index.scan(roots: [root], useHistory: true)
        XCTAssertEqual(stats.diffRoots, 1)
        XCTAssertEqual(index.sets.map(\.name).sorted(), ["A", "C"])
    }

    /// The real journal, on a temp folder: whatever the system recorded since an event id comes back
    /// as events under the root (skipped where the volume keeps no history).
    func testRealJournalReplayFindsAFileCreatedAfterTheMark() throws {
        let t = makeTemp("replay")
        let root = t.mkdir("music")
        let identity = RootIdentity.of(root)
        try XCTSkipUnless(identity.deviceUUID != nil && identity.isLocal, "no event journal here")
        Thread.sleep(forTimeInterval: 1.0)      // let the folder's own creation settle before the mark
        let mark = FSEventsGetCurrentEventId()
        t.als("music/N Project/N.als", Fx.simpleSet())
        Thread.sleep(forTimeInterval: 1.0)
        let outcome = FSEventsReplay.events(root: root, since: mark, timeout: 15)
        guard case .events(let events) = outcome else { return XCTFail("replay failed: \(outcome)") }
        let seen = events.contains { $0.path.hasSuffix("N Project/N.als") || $0.path.hasSuffix("N Project") }
        XCTAssertTrue(seen, "events: \(events.map(\.path))")
        XCTAssertEqual(DiffScan.plan(for: outcome, root: root, projectDirs: []), .regions([t.sub("music/N Project")]))
    }
}
