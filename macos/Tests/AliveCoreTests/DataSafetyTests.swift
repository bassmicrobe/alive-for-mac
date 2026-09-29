import XCTest
@testable import AliveCore

/// Crafted inputs: a decompression bomb, a broken cache, out-of-range numbers. Each of these
/// crashed or lost data before; they must now end in an error value or an empty result.
final class GzipSafetyTests: XCTestCase {
    private func zeros(_ n: Int) -> Data { Data(count: n) }

    func testInflateBombIsCapped() throws {
        let bomb = try Gzip.compress(zeros(8 * 1024 * 1024))
        XCTAssertLessThan(bomb.count, 64 * 1024, "the bomb is tiny on disk")
        XCTAssertThrowsError(try Gzip.decompress(bomb, limit: 1024 * 1024)) {
            XCTAssertEqual($0 as? GzipError, .tooLarge)
        }
        XCTAssertEqual(try Gzip.decompress(bomb, limit: 8 * 1024 * 1024).count, 8 * 1024 * 1024)
    }

    func testReadMaybeGzipCapsGzipAndPlainFiles() throws {
        let t = makeTemp()
        let gz = t.sub("bomb.als")
        try Gzip.compress(zeros(4 * 1024 * 1024)).write(to: URL(fileURLWithPath: gz))
        XCTAssertThrowsError(try Gzip.readMaybeGzip(path: gz, limit: 1024)) { XCTAssertEqual($0 as? GzipError, .tooLarge) }
        let plain = t.write("plain.als", String(repeating: "<a/>", count: 1000))
        XCTAssertThrowsError(try Gzip.readMaybeGzip(path: plain, limit: 100)) { XCTAssertEqual($0 as? GzipError, .tooLarge) }
        XCTAssertEqual(try Gzip.readMaybeGzip(path: plain).count, 4000)
    }

    /// Output that ends exactly on the reader's buffer boundary used to leave zlib holding
    /// pending bytes with all input consumed: a valid file then read as "truncated".
    func testLineReaderHandlesOutputBufferBoundaries() throws {
        let t = makeTemp()
        let chunk = 256 * 1024
        for lines in [chunk / 1024, 4 * chunk / 1024, 33 * chunk / 1024] {
            let line = String(repeating: "x", count: 1023) + "\n"
            let path = t.sub("b\(lines).als")
            try Gzip.compress(Data(String(repeating: line, count: lines).utf8)).write(to: URL(fileURLWithPath: path))
            let reader = try GzipLineReader(path: path)
            var n = 0
            while let l = try reader.next() { XCTAssertEqual(l.count, 1024); n += 1 }
            XCTAssertEqual(n, lines)
        }
    }

    func testLineReaderRefusesAnEndlessLine() throws {
        let t = makeTemp()
        let path = t.sub("one-line.als")
        try Gzip.compress(Data(repeating: 0x61, count: 4 * 1024 * 1024)).write(to: URL(fileURLWithPath: path))
        let reader = try GzipLineReader(path: path, maxLine: 1024 * 1024)
        XCTAssertThrowsError(try reader.next()) { XCTAssertEqual($0 as? GzipError, .tooLarge) }

        let total = try GzipLineReader(path: path, maxTotal: 512 * 1024)
        XCTAssertThrowsError(try total.next()) { XCTAssertEqual($0 as? GzipError, .tooLarge) }
    }

    func testWriterNeverTouchesAnExistingFile() throws {
        let t = makeTemp()
        let mine = t.write("Song.alive-probe.als", "somebody's own file")
        XCTAssertThrowsError(try GzipLineWriter(path: mine))
        XCTAssertEqual(try String(contentsOfFile: mine), "somebody's own file")
    }
}

final class ParserSafetyTests: XCTestCase {
    func testAHugeScaleRootIsClampedAtParseTime() {
        let xml = Fx.als(live: Fx.tracks(Fx.track("AudioTrack")) + Fx.main(tempo: 120)
                         + "<ScaleInformation><Root Value=\"99999999999\"/><Name Value=\"-99999999999\"/></ScaleInformation>")
        let info = AlsFile.parse(xml: Data(xml.utf8))
        XCTAssertNil(info.error)
        XCTAssertEqual(info.scaleRoot, -1)
        XCTAssertEqual(info.scaleIndex, -1)
    }

    func testTheIndexCacheWritesExtremeValuesWithoutTrapping() {
        let t = makeTemp()
        var e = SetEntry()
        e.path = "/x/a.als"; e.name = "a"
        e.scaleRoot = 99_999_999_999; e.scaleIndex = -99_999_999_999
        e.tracks = Int.max; e.missingFiles = Int.min; e.totalRefs = 1 << 40
        IndexCache.save([e], dir: t.path)
        let back = IndexCache.load(dir: t.path)["/x/a.als"]
        XCTAssertEqual(back?.scaleRoot, Int(Int32.max))
        XCTAssertEqual(back?.tracks, Int(Int32.max))
        XCTAssertEqual(back?.missingFiles, Int(Int32.min))
    }

    func testOutOfRangeTicksInTheIndexCacheMeanNoCache() throws {
        let t = makeTemp()
        IndexCache.save([SetEntry()], dir: t.path)
        let path = IndexCache.path(dir: t.path)
        var data = try Data(contentsOf: URL(fileURLWithPath: path))
        // version, count, three empty strings, then the "modified" ticks.
        withUnsafeBytes(of: Int64.max.littleEndian) { data.replaceSubrange(11..<19, with: $0) }
        try data.write(to: URL(fileURLWithPath: path))
        XCTAssertTrue(IndexCache.load(dir: t.path).isEmpty)
    }

    func testTicksHelpersNeverTrap() {
        XCTAssertFalse(DotNetTicks.isValid(ticks: Int64.min))
        XCTAssertFalse(DotNetTicks.isValid(ticks: Int64.max))
        _ = DotNetTicks.date(utc: Int64.min)
        _ = DotNetTicks.date(utc: Int64.max)
        _ = DotNetTicks.date(local: Int64.max)
        _ = DotNetTicks.utc(Date.distantFuture)
        _ = DotNetTicks.utc(Date(timeIntervalSince1970: .infinity))
        _ = DotNetTicks.local(Date.distantPast)
    }

    func testActivityCacheSkipsCorruptTicks() throws {
        let t = makeTemp()
        var w = DotNetWriter()
        w.int32(Activity.cacheVersion); w.int32(3)
        w.int64(Int64.min)
        w.int64(DotNetTicks.local(Date(timeIntervalSince1970: 1_700_000_000)))
        w.int64(Int64.max)
        try w.data.write(to: URL(fileURLWithPath: Activity.cachePath(dir: t.path)))
        XCTAssertEqual(Activity.loadCache(dir: t.path).total, 1)
    }

    func testATagWithManyAttributesIsRefused() {
        var attrs = ""
        for i in 0..<5000 { attrs += " a\(i)=\"1\"" }
        let xml = "<?xml version=\"1.0\"?><Ableton><Big\(attrs)/></Ableton>"
        var error: String?
        let stream = ElementStream(onStart: { _ in }, onEnd: { _ in })
        error = stream.run(Data(xml.utf8))
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("too many attributes") ?? false)
    }
}

final class CacheSafetyTests: XCTestCase {
    private func cache(folders: Int32, then build: (inout DotNetWriter) -> Void = { _ in }) -> Data {
        var w = DotNetWriter()
        w.int32(SampleCache.version)
        w.int32(folders)
        build(&w)
        return w.data
    }

    func testDamagedSampleCacheCountsAreErrorsNotCrashes() {
        for count in [Int32(-1), Int32.min, Int32.max, 1_000_000] {
            XCTAssertThrowsError(try SampleCache.decode(cache(folders: count)), "folders=\(count)")
        }
        // Valid folder section, then a negative / absurd file count and root count.
        func withFolder(_ files: Int32, roots: Int32 = 0) -> Data {
            cache(folders: 1) { w in
                w.string("/root"); w.int32(-1); w.int32(0); w.int64(0); w.int64(0); w.int64(0)
                w.int32(files)
                if files == 0 { w.int32(roots) }
            }
        }
        XCTAssertThrowsError(try SampleCache.decode(withFolder(-7)))
        XCTAssertThrowsError(try SampleCache.decode(withFolder(Int32.max)))
        XCTAssertThrowsError(try SampleCache.decode(withFolder(0, roots: -3)))
        XCTAssertThrowsError(try SampleCache.decode(withFolder(0, roots: Int32.max)))
    }

    func testAnUnreadableSampleCacheLoadsAsEmpty() throws {
        let t = makeTemp()
        try cache(folders: Int32.max).write(to: URL(fileURLWithPath: SampleCache.path(dir: t.path)))
        XCTAssertTrue(SampleCache.load(dir: t.path).folders.isEmpty)
    }

    func testTheSampleCacheRoundTripStillWorks() throws {
        var idx = SampleIndex()
        var f = SampleFolder(); f.path = "/lib"; f.name = "/lib"
        idx.folders = [f]
        idx.roots = [0]
        let back = try SampleCache.decode(SampleCache.encode(idx))
        XCTAssertEqual(back.folders.count, 1)
        XCTAssertEqual(back.roots, [0])
    }

    func testAnAiffWithAnInfiniteSampleRateIsJustNotAnAiff() throws {
        func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
        var comm: [UInt8] = [0, 2] + be32(100) + [0, 16]
        comm += [0x7F, 0xFF, 0x80, 0, 0, 0, 0, 0, 0, 0]          // exponent 0x7FFF: infinity
        var bytes = Array("FORM".utf8) + be32(4 + 8 + 18 + 8 + 4) + Array("AIFF".utf8)
        bytes += Array("COMM".utf8) + be32(18) + comm
        bytes += Array("SSND".utf8) + be32(4) + [0, 0, 0, 0]
        let t = makeTemp()
        let path = t.sub("inf.aif")
        try Data(bytes).write(to: URL(fileURLWithPath: path))
        XCTAssertNil(AiffReader.readHeader(path: path))          // used to trap in Int(inf)

        var nan = bytes
        nan.replaceSubrange((12 + 8 + 8)..<(12 + 8 + 18), with: [0x7F, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0])
        try Data(nan).write(to: URL(fileURLWithPath: path))
        XCTAssertNil(AiffReader.readHeader(path: path))
    }
}

final class UpdateBodyCapTests: XCTestCase {
    func testAnOversizedReplyIsNotParsed() {
        let json = "{\"tag_name\":\"v9.0.0\",\"pad\":\"" + String(repeating: "a", count: UpdateCheck.maxBodyBytes) + "\"}"
        XCTAssertEqual(UpdateCheck.outcome(status: 200, body: Data(json.utf8), current: "0.1.0"), .failed(.unexpectedAnswer))
    }
}

final class TextFileSafetyTests: XCTestCase {
    func testABOMDoesNotHideTheFirstKey() throws {
        let t = makeTemp()
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("root=/first\nroot=/second\n".utf8))
        try data.write(to: URL(fileURLWithPath: Settings.filePath(dir: t.path)))
        XCTAssertEqual(Settings.load(dir: t.path).roots, ["/first", "/second"])
    }

    func testMissingAndUnreadableAreDifferent() throws {
        let t = makeTemp()
        XCTAssertEqual(AppHome.readConfig(t.sub("none.cfg")), .missing)

        let bin = t.sub("bin.cfg")
        try Data([0x72, 0x6F, 0x00, 0xFF, 0xFE, 0x00, 0x01]).write(to: URL(fileURLWithPath: bin))
        XCTAssertEqual(AppHome.readConfig(bin), .unreadable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bin + ".bak"), "backed up before anything can overwrite it")
        XCTAssertTrue(AppHome.takeBackupNotices().contains("bin.cfg"))
        XCTAssertEqual(AppHome.readConfig(bin), .unreadable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bin + ".bak2"), "the same content is backed up once")
    }

    func testInvalidUTF8IsRecoveredAndTheOriginalKept() throws {
        let t = makeTemp()
        let path = Settings.filePath(dir: t.path)
        // "root=/Caf\u{E9}" in Latin-1: the byte E9 alone is not valid UTF-8.
        let original = Data([UInt8]("root=/Caf".utf8) + [0xE9, 0x0A])
        try original.write(to: URL(fileURLWithPath: path))
        let s = Settings.load(dir: t.path)
        XCTAssertEqual(s.roots, ["/Caf\u{E9}"])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path + ".bak")), original)
    }

    func testUTF16FilesFromWindowsAreRead() throws {
        let t = makeTemp()
        let path = t.sub("home.cfg")
        try "pin=/a\r\npin=/b\r\n".data(using: .utf16)!.write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(AppHome.readConfig(path), .lines(["pin=/a", "pin=/b", ""]))
    }

    func testSettingsWithLineBreaksInValuesDoNotCorruptTheFile() {
        let t = makeTemp()
        var s = Settings()
        s.roots = ["/ok", "/bad\nroot=/injected", "/bad2\r"]
        s.pluginSource = "x\ny"
        s.unknownLines = ["# my own comment", "future_key=1"]
        XCTAssertNoThrow(try s.save(dir: t.path))
        let back = Settings.load(dir: t.path)
        XCTAssertEqual(back.roots, ["/ok"])
        XCTAssertEqual(back.pluginSource, "")
        XCTAssertEqual(back.unknownLines, ["# my own comment", "future_key=1"])
        // and a second save/load cycle changes nothing
        XCTAssertNoThrow(try back.save(dir: t.path))
        XCTAssertEqual(Settings.load(dir: t.path), back)
    }

    func testTheLogRedactsTheHomeFolder() {
        XCTAssertEqual(Diag.redacted("cannot copy /Users/jane/Music/x.wav", home: "/Users/jane"),
                       "cannot copy ~/Music/x.wav")
        XCTAssertEqual(Diag.redacted("path /x", home: "/"), "path /x")
        XCTAssertEqual(Diag.redacted("/Users/janedoe/x and /Users/jane", home: "/Users/jane"),
                       "/Users/janedoe/x and ~", "another user's folder is not rewritten")
    }
}
