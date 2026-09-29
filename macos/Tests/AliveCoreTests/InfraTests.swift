import XCTest
@testable import AliveCore

final class SettingsTests: XCTestCase {
    func testDefaultsMatchUpstream() {
        let s = Settings()
        XCTAssertTrue(s.isFirstRun)
        XCTAssertTrue(s.disableGlass)
        XCTAssertFalse(s.smoothScroll)
        XCTAssertTrue(s.groupByFolder)
        XCTAssertTrue(s.overviewOpen)
        XCTAssertTrue(s.vst3SystemOn)
        XCTAssertTrue(s.collectElsewhere)
        XCTAssertFalse(s.collectFactoryPacks)
        XCTAssertFalse(s.checkUpdates)
        XCTAssertEqual(s.lang, "system")
    }

    func testMissingFileGivesDefaults() {
        let t = makeTemp()
        XCTAssertEqual(Settings.load(dir: t.sub("nothing")), Settings())
    }

    func testFullRoundTripIncludingLangAndUnknownKeys() throws {
        let t = makeTemp()
        var s = Settings()
        s.roots = ["/a/one", "/b/two"]
        s.disabledRoots = ["/b/two"]
        s.sampleRoots = ["/samples"]
        s.disabledSampleRoots = ["/samples"]
        s.setColumns = "Set,Modified:150"; s.pluginColumns = "Name"; s.sampleColumns = "Name,Location:140"
        s.columnsSorted = true; s.pinnedFirst = true; s.overviewOpen = false
        s.disableGlass = false; s.smoothScroll = true; s.groupByFolder = false
        s.pluginsFromFolders = true; s.pluginSource = "Live 12.0b20"
        s.vst2CustomOn = true; s.vst2CustomPath = "/vst"; s.vst3SystemOn = false
        s.vst3CustomOn = true; s.vst3CustomPath = "/vst3"
        s.collectElsewhere = false; s.collectOtherProjects = false; s.collectUserLibrary = false
        s.collectFactoryPacks = true; s.collectToZip = true
        s.windowBounds = "1,2,3,4"; s.windowMaximized = true
        s.checkUpdates = true; s.lastUpdateCheck = "2026-09-29"; s.seenUpdate = "1.2.3"
        s.lang = "ja"
        s.unknownLines = ["futurekey=some value", "another=1"]
        try s.save(dir: t.path)

        let back = Settings.load(dir: t.path)
        XCTAssertEqual(back, s)
        XCTAssertFalse(back.isFirstRun)
        // A second save writes byte-identical text.
        try back.save(dir: t.path)
        XCTAssertEqual(try String(contentsOfFile: Settings.filePath(dir: t.path)), s.serialized())
    }

    func testFormatIsUpstreamsLineFormat() {
        var s = Settings()
        s.roots = ["/r"]
        let text = s.serialized()
        XCTAssertTrue(text.hasPrefix("# Alive - folders to scan for projects\nroot=/r\npinnedfirst=0\noverviewopen=1\nnoglass=1\n"))
        XCTAssertTrue(text.contains("vst3system=1\n"))
        XCTAssertFalse(text.contains("setcolumns"))        // empty optional keys are omitted
        XCTAssertTrue(text.hasSuffix("lang=system\n"))
    }

    func testLoadParsingRules() throws {
        let t = makeTemp()
        t.write("settings.cfg", """
        # comment
        root = /A/x
        root=/a/X
        root_off=/A/x
        nosmoothscroll=0
        garbage line without equals
        lang=fr
        unknown_thing=keep me
          spaced = value
        """)
        let s = Settings.load(dir: t.path)
        XCTAssertEqual(s.roots, ["/A/x"])                  // case-insensitive duplicate dropped
        XCTAssertEqual(s.disabledRoots, ["/A/x"])
        XCTAssertTrue(s.smoothScroll)                      // legacy nosmoothscroll=0
        XCTAssertEqual(s.lang, "system")                   // invalid language falls back
        XCTAssertEqual(s.unknownLines, ["unknown_thing=keep me", "spaced = value"])
    }

    func testReloadRoots() throws {
        let t = makeTemp()
        var a = Settings(); a.roots = ["/one"]; a.disabledRoots = ["/one"]
        try a.save(dir: t.path)
        var b = Settings(); b.roots = ["/stale"]; b.pinnedFirst = true
        b.reloadRoots(dir: t.path)
        XCTAssertEqual(b.roots, ["/one"])
        XCTAssertEqual(b.disabledRoots, ["/one"])
        XCTAssertTrue(b.pinnedFirst)
    }
}

final class AppHomeDiagTests: XCTestCase {
    func testAtomicWriteAndReadLines() throws {
        let t = makeTemp()
        let p = t.sub("deep/er/file.txt")
        try AppHome.writeAtomically("a\r\nb\nc", to: p)
        XCTAssertEqual(AppHome.readLines(p), ["a", "b", "c"])
        XCTAssertNil(AppHome.readLines(t.sub("missing")))
        XCTAssertEqual(AppHome.file("x.cfg", in: "/d"), "/d/x.cfg")
    }

    func testEnsureCreatesFolder() throws {
        let t = makeTemp()
        let d = try AppHome.ensure(t.sub("a/b"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: d))
        XCTAssertFalse(AppHome.path.isEmpty)
    }

    func testDiagWritesAndTruncates() throws {
        let t = makeTemp()
        Diag.start(dir: t.path)
        Diag.info("hello")
        Diag.warn("careful")
        Diag.fail("thing", NSError(domain: "x", code: 1))
        Diag.fail("thing2", nil)
        let log = try String(contentsOfFile: Diag.defaultLogPath(dir: t.path))
        XCTAssertTrue(log.contains("Alive for Mac"))
        XCTAssertTrue(log.contains("hello"))
        XCTAssertTrue(log.contains("WARN careful"))
        XCTAssertTrue(log.contains("thing FAILED"))
        XCTAssertTrue(log.contains("unknown error"))
        XCTAssertEqual(Diag.currentLogPath, Diag.defaultLogPath(dir: t.path))

        Diag.start(dir: t.path)                       // truncated at each start
        let again = try String(contentsOfFile: Diag.defaultLogPath(dir: t.path))
        XCTAssertFalse(again.contains("hello"))
        Diag.stop()
        Diag.info("after stop")                        // no-op, must not crash
        XCTAssertNil(Diag.currentLogPath)
    }
}

final class DotNetBinaryTests: XCTestCase {
    func testKnownByteLayout() {
        var w = DotNetWriter()
        w.int32(11); w.int64(1); w.bool(true); w.string("héllo")
        // 11 LE, 1 LE, true, length 6 (é is 2 bytes) + UTF-8
        XCTAssertEqual(Array(w.data), [11, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 6, 0x68, 0xC3, 0xA9, 0x6C, 0x6C, 0x6F])
    }

    func testLongStringUsesSevenBitLength() throws {
        var w = DotNetWriter()
        let s = String(repeating: "a", count: 300)
        w.string(s)
        XCTAssertEqual(Array(w.data.prefix(2)), [0xAC, 0x02])     // 300 = 0b1_0010_1100
        var r = DotNetReader(w.data)
        XCTAssertEqual(try r.string(), s)
        XCTAssertTrue(r.isAtEnd)
    }

    func testRoundTripAndTruncation() throws {
        var w = DotNetWriter()
        w.double(128.5); w.int32(-7); w.string("")
        var r = DotNetReader(w.data)
        XCTAssertEqual(try r.double(), 128.5)
        XCTAssertEqual(try r.int32(), -7)
        XCTAssertEqual(try r.string(), "")
        XCTAssertThrowsError(try r.int32())
        var bad = DotNetReader(Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]))
        XCTAssertThrowsError(try bad.string())
    }

    func testTicks() {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(DotNetTicks.utc(Date(timeIntervalSince1970: 0)), 621_355_968_000_000_000)
        XCTAssertTrue(DotNetTicks.sameInstant(DotNetTicks.date(utc: DotNetTicks.utc(d)), d))
        XCTAssertTrue(DotNetTicks.sameInstant(DotNetTicks.date(local: DotNetTicks.local(d)), d))
    }
}

final class ParallelTests: XCTestCase {
    func testMapVisitsEveryIndexOnceAndHonoursCancellation() {
        let r = Parallel.map(count: 500) { $0 * 2 }
        XCTAssertEqual(r.compactMap { $0 }, (0..<500).map { $0 * 2 })
        let none = Parallel.map(count: 50, isCancelled: { true }) { $0 }
        XCTAssertTrue(none.allSatisfy { $0 == nil })
        XCTAssertTrue(Parallel.map(count: 0) { $0 }.isEmpty)
    }
}
