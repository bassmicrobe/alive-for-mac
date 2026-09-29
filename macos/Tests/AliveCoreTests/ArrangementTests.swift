import XCTest
@testable import AliveCore

final class ArrangementTests: XCTestCase {
    private func clip(_ tag: String, start: Double, end: Double, name: String, color: Int,
                      notes: String = "", loopOn: Bool = false) -> String {
        "<\(tag) Id=\"3\" Time=\"\(start)\"><CurrentStart Value=\"\(start)\"/><CurrentEnd Value=\"\(end)\"/>"
            + "<Loop><LoopStart Value=\"0\"/><LoopEnd Value=\"\(end - start)\"/><StartRelative Value=\"0\"/>"
            + "<LoopOn Value=\"\(loopOn)\"/></Loop><Name Value=\"\(name)\"/><Color Value=\"\(color)\"/>"
            + "<Disabled Value=\"false\"/>\(notes)</\(tag)>"
    }

    private func arranger(_ clips: String) -> String {
        "<DeviceChain><MainSequencer><Sample><ArrangerAutomation><Events>\(clips)</Events></ArrangerAutomation></Sample>"
            + "<ClipSlotList><ClipSlot><ClipSlot><Value>\(clip("AudioClip", start: 0, end: 500, name: "session", color: 1))"
            + "</Value></ClipSlot></ClipSlot></ClipSlotList></MainSequencer></DeviceChain>"
    }

    private func notes(_ keys: [(Int, [(Double, Double, Int)])]) -> String {
        "<Notes><KeyTracks>" + keys.map { key, evs in
            "<KeyTrack Id=\"1\"><Notes>"
                + evs.map { "<MidiNoteEvent Time=\"\($0.0)\" Duration=\"\($0.1)\" Velocity=\"\($0.2)\"/>" }.joined()
                + "</Notes><MidiKey Value=\"\(key)\"/></KeyTrack>"
        }.joined() + "</KeyTracks></Notes>"
    }

    private func parse(_ live: String) -> Arrangement {
        Arrangement.parse(xml: Data(Fx.als(live: live).utf8), path: "/x.als")
    }

    func testClipsOnRulerSessionClipsIgnored() throws {
        let audio = Fx.track("AudioTrack", id: 1, name: "Drums",
                             extra: "<Color Value=\"14\"/>" + arranger(clip("AudioClip", start: 4, end: 36, name: "den", color: 23)))
        let a = parse(Fx.tracks(audio) + Fx.main(tempo: 111))
        XCTAssertNil(a.error)
        XCTAssertEqual(a.path, "/x.als")
        XCTAssertEqual(a.creator, "Ableton Live 12.3.5")
        XCTAssertEqual(a.tempo, 111)
        XCTAssertEqual(a.clipCount, 1)
        let t = try XCTUnwrap(a.tracks.first)
        XCTAssertEqual(t.name, "Drums")
        XCTAssertEqual(t.color, 14)
        let c = try XCTUnwrap(t.clips.first)
        XCTAssertEqual(c.name, "den")
        XCTAssertEqual(c.color, 23)
        XCTAssertEqual(c.start, 4); XCTAssertEqual(c.end, 36)
        XCTAssertEqual(c.length, 32); XCTAssertEqual(c.loopLength, 32)
        XCTAssertFalse(c.isMidi)
        XCTAssertEqual(a.end, 36)
        XCTAssertEqual(a.bars, 9)
        XCTAssertTrue(a.hasContent)
    }

    func testMidiNotesGetPitchFromTrailingMidiKey() throws {
        let n = notes([(60, [(0, 1, 100), (2, 1, 90)]), (64, [(1, 0.5, 300)])])
        let midi = Fx.track("MidiTrack", extra: arranger(clip("MidiClip", start: 0, end: 8, name: "m", color: 3, notes: n, loopOn: true)))
        let a = parse(Fx.tracks(midi))
        let c = try XCTUnwrap(a.tracks.first?.clips.first)
        XCTAssertTrue(c.isMidi)
        XCTAssertTrue(c.loopOn)
        XCTAssertEqual(c.notes?.count, 3)
        XCTAssertEqual(c.notes?.map(\.pitch), [60, 60, 64])
        XCTAssertEqual(c.notes?[2].velocity, 127)         // clamped
        XCTAssertEqual(c.minPitch, 60); XCTAssertEqual(c.maxPitch, 64)
        XCTAssertEqual(a.noteCount, 3)
    }

    func testJunkClipDroppedAndMinimumEnd() {
        let audio = Fx.track("AudioTrack", extra: arranger(clip("AudioClip", start: 8, end: 8, name: "z", color: 1)))
        let a = parse(Fx.tracks(audio))
        XCTAssertEqual(a.clipCount, 0)
        XCTAssertFalse(a.hasContent)
        XCTAssertEqual(a.end, 4)
    }

    func testGroupIndentAndColorFallbackFromClips() {
        let group = Fx.track("GroupTrack", id: 10, name: "G")
        let child = Fx.track("AudioTrack", id: 11, name: "C",
                             extra: "<TrackGroupId Value=\"10\"/>" + arranger(
                                clip("AudioClip", start: 0, end: 4, name: "a", color: 7)
                                    + clip("AudioClip", start: 4, end: 8, name: "b", color: 7)
                                    + clip("AudioClip", start: 8, end: 12, name: "c", color: 9)))
        let a = parse(Fx.tracks(group + child))
        XCTAssertEqual(a.tracks.map(\.indent), [0, 1])
        XCTAssertTrue(a.tracks[0].isGroup)
        XCTAssertEqual(a.tracks[1].groupId, 10)
        XCTAssertEqual(a.tracks[1].color, 7)     // most common clip colour
    }

    func testOldColorIndexShiftsAndFrozenFlag() {
        let t1 = Fx.track("AudioTrack", id: 1, extra: "<ColorIndex Value=\"150\"/><Freeze Value=\"true\"/>")
        let t2 = Fx.track("AudioTrack", id: 2, extra: "<ColorIndex Value=\"282\"/>")
        let t3 = Fx.track("AudioTrack", id: 3, extra: "<ColorIndex Value=\"1000\"/>")
        let a = parse(Fx.tracks(t1 + t2 + t3))
        XCTAssertEqual(a.tracks.map(\.color), [10, 64, -1])
        XCTAssertTrue(a.tracks[0].frozen)
        XCTAssertEqual(ArrangementParser.palette(-5), -1)
    }

    func testMainTrackNameIsNotATrackLaneAndTempoOnlyFromMain() {
        let clipTempo = "<Tempo><Manual Value=\"77\"/></Tempo>"
        let a = parse(Fx.tracks(Fx.track("AudioTrack", extra: clipTempo)) + Fx.main(tag: "MasterTrack", tempo: 100))
        XCTAssertEqual(a.tempo, 100)
        XCTAssertEqual(a.tracks.count, 1)
    }

    func testNoteCapAcrossTheSet() {
        var evs: [(Double, Double, Int)] = []
        for i in 0..<10 { evs.append((Double(i), 1, 100)) }
        let midi = Fx.track("MidiTrack", extra: arranger(clip("MidiClip", start: 0, end: 16, name: "m", color: 1, notes: notes([(60, evs)]))))
        XCTAssertEqual(parse(Fx.tracks(midi)).noteCount, 10)
        XCTAssertEqual(Arrangement.maxNotes, 200_000)
    }

    func testReadMissingFileGivesErrorAndDefaults() {
        let a = Arrangement.read(path: "/no/such.als")
        XCTAssertNotNil(a.error)
        XCTAssertEqual(a.end, 4)
    }

    func testReadFromDisk() throws {
        let t = makeTemp()
        let audio = Fx.track("AudioTrack", extra: arranger(clip("AudioClip", start: 0, end: 16, name: "x", color: 2)))
        let p = t.als("s.als", Fx.als(live: Fx.tracks(audio)))
        XCTAssertEqual(Arrangement.read(path: p).clipCount, 1)
    }
}

final class ArrangementLoaderTests: XCTestCase {
    private func makeSet(_ t: TempDir, _ name: String) -> String {
        let clip = "<AudioClip><CurrentStart Value=\"0\"/><CurrentEnd Value=\"8\"/><Name Value=\"c\"/></AudioClip>"
        let track = Fx.track("AudioTrack", extra: "<DeviceChain><Sample><ArrangerAutomation><Events>\(clip)</Events></ArrangerAutomation></Sample></DeviceChain>")
        return t.als(name, Fx.als(live: Fx.tracks(track)))
    }

    func testAsyncLoadCachesAndDeduplicates() async {
        let t = makeTemp()
        let path = makeSet(t, "a.als")
        let loader = ArrangementLoader()
        XCTAssertNil(loader.cached(path))
        async let x = loader.load(path)
        async let y = loader.load(path)
        let (a, b) = await (x, y)
        XCTAssertEqual(a.clipCount, 1)
        XCTAssertEqual(b.clipCount, 1)
        XCTAssertNotNil(loader.cached(path))
        let again = await loader.load(path)
        XCTAssertEqual(again.clipCount, 1)
    }

    func testCancelledWaitersLeaveAtOnceAndLeaveNothingBehind() async {
        let t = makeTemp()
        let loader = ArrangementLoader()
        // Far more parses than workers: most of them are still queued when their tasks are cancelled.
        let paths = (0..<12).map { makeSet(t, "c\($0).als") }
        let tasks = paths.map { path in Task { await loader.load(path) } }
        tasks.forEach { $0.cancel() }
        var cancelled = 0
        for task in tasks {
            let a = await task.value
            if a.error == "cancelled" { cancelled += 1 } else { XCTAssertEqual(a.clipCount, 1, "or it had already been parsed") }
        }
        XCTAssertGreaterThan(cancelled, 0, "at least the tasks cancelled before they ran gave up")
        for path in paths { XCTAssertEqual(loader.waiterCount(path), 0) }
        // The loader still works after the storm.
        let fresh = await loader.load(paths[0])
        XCTAssertEqual(fresh.clipCount, 1)
    }

    func testATaskCancelledBeforeItLoadsNeverQueuesAParse() async {
        let t = makeTemp()
        let path = makeSet(t, "a.als")
        let loader = ArrangementLoader()
        let task = Task { () -> Arrangement in
            while !Task.isCancelled { await Task.yield() }
            return await loader.load(path)
        }
        task.cancel()
        let a = await task.value
        XCTAssertEqual(a.error, "cancelled")
        XCTAssertEqual(loader.waiterCount(path), 0)
        XCTAssertNil(loader.cached(path), "nothing was parsed for a task nobody waited for")
    }

    func testRequestFiresOnReadyAndCacheEvicts() {
        let t = makeTemp()
        let loader = ArrangementLoader()
        let paths = (0..<(ArrangementLoader.cacheSize + 4)).map { makeSet(t, "s\($0).als") }
        let ready = expectation(description: "ready")
        ready.expectedFulfillmentCount = paths.count
        loader.onReady = { _ in ready.fulfill() }
        paths.forEach { loader.request($0) }
        loader.request("")
        wait(for: [ready], timeout: 20)
        let cachedCount = paths.filter { loader.cached($0) != nil }.count
        XCTAssertLessThanOrEqual(cachedCount, ArrangementLoader.cacheSize)
        XCTAssertNil(loader.cached(""))
    }

    func testResavedSetIsReparsedNotServedFromTheCache() async {
        let t = makeTemp()
        let path = makeSet(t, "a.als")
        let loader = ArrangementLoader()
        let first = await loader.load(path)
        XCTAssertEqual(first.clipCount, 1)
        // Re-save with two clips and another modification time.
        let clip = "<AudioClip><CurrentStart Value=\"0\"/><CurrentEnd Value=\"8\"/><Name Value=\"c\"/></AudioClip>"
        let track = Fx.track("AudioTrack", extra: "<DeviceChain><Sample><ArrangerAutomation><Events>\(clip)\(clip)</Events></ArrangerAutomation></Sample></DeviceChain>")
        _ = t.als("a.als", Fx.als(live: Fx.tracks(track)))
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 120)], ofItemAtPath: path)
        XCTAssertNil(loader.cached(path), "a stale entry is not served")
        let second = await loader.load(path)
        XCTAssertEqual(second.clipCount, 2)
        XCTAssertNotNil(loader.cached(path))
    }

    func testLoadOfEmptyPathCompletesAndDoesNotLeak() async {
        let loader = ArrangementLoader()
        for _ in 0..<5 {
            let a = await loader.load("")
            XCTAssertFalse(a.hasContent)
        }
    }
}
