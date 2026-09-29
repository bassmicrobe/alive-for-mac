import XCTest
@testable import AliveCore

/// Tiny audio files generated in code.
enum SampleFixtures {
    static func be(_ v: UInt64, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> UInt64(8 * (n - 1 - $0))) & 0xFF) } }
    static func le(_ v: UInt64, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> UInt64(8 * $0)) & 0xFF) } }

    /// 80-bit extended for a whole number of Hz.
    static func extended(_ rate: Int) -> [UInt8] {
        let e = 63 - rate.leadingZeroBitCount
        return be(UInt64(e + 16383), 2) + be(UInt64(rate) << UInt64(63 - e), 8)
    }

    static func wav(frames: Int = 100, rate: Int = 44100, channels: Int = 1, bits: Int = 16, seed: UInt8 = 0) -> Data {
        let block = channels * bits / 8
        let dataSize = frames * block
        var d = Array("RIFF".utf8) + le(UInt64(36 + dataSize), 4) + Array("WAVE".utf8)
        d += Array("fmt ".utf8) + le(16, 4) + le(1, 2) + le(UInt64(channels), 2) + le(UInt64(rate), 4)
        d += le(UInt64(rate * block), 4) + le(UInt64(block), 2) + le(UInt64(bits), 2)
        d += Array("data".utf8) + le(UInt64(dataSize), 4) + [UInt8](repeating: seed, count: dataSize)
        return Data(d)
    }

    /// AIFF, or AIFC when `compression` is given ("sowt", "able"…).
    static func aiff(frames: Int = 100, rate: Int = 44100, channels: Int = 1, bits: Int = 16,
                     compression: String? = nil, seed: UInt8 = 0) -> Data {
        let dataSize = frames * channels * bits / 8
        var comm = be(UInt64(channels), 2) + be(UInt64(frames), 4) + be(UInt64(bits), 2) + extended(rate)
        if let compression { comm += Array(compression.utf8) + [0, 0] }      // empty pascal name, padded
        var body = Array((compression == nil ? "AIFF" : "AIFC").utf8)
        if compression != nil { body += Array("FVER".utf8) + be(4, 4) + be(0xA280_5140, 4) }
        body += Array("COMM".utf8) + be(UInt64(comm.count), 4) + comm
        body += Array("SSND".utf8) + be(UInt64(8 + dataSize), 4) + be(0, 4) + be(0, 4)
            + [UInt8](repeating: seed, count: dataSize)
        return Data(Array("FORM".utf8) + be(UInt64(body.count), 4) + body)
    }

    @discardableResult
    static func put(_ data: Data, at path: String) -> String {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try! data.write(to: URL(fileURLWithPath: path))
        return path
    }
}

final class SampleIndexTests: XCTestCase {
    private func tree() -> (TempDir, String) {
        let t = makeTemp("samples")
        let root = t.mkdir("Lib")
        SampleFixtures.put(SampleFixtures.wav(seed: 1), at: root + "/Kicks/a.wav")
        SampleFixtures.put(SampleFixtures.aiff(seed: 2), at: root + "/Kicks/b.aif")
        SampleFixtures.put(SampleFixtures.wav(seed: 3), at: root + "/Pads/Deep/c.WAV")
        t.write("Lib/Pads/readme.txt", "hello")
        t.write("Lib/Kicks/._a.wav", "resource fork")
        SampleFixtures.put(Data("ogg".utf8), at: root + "/Ableton Folder Info/preview.ogg")
        SampleFixtures.put(SampleFixtures.wav(seed: 4), at: root + "/Song Project/rec.wav")
        SampleFixtures.put(SampleFixtures.wav(seed: 5), at: root + "/Backup/old.wav")
        t.write("Lib/Empty/notes.txt", "nothing here")
        return (t, root)
    }

    func testWalkKeepsOnlyFoldersWithSamples() {
        let (_, root) = tree()
        let idx = SampleIndex.build(roots: [root], disabled: [])
        XCTAssertEqual(idx.roots, [0])
        XCTAssertEqual(idx.folders.map(\.name).sorted(), [SampleIndex.norm(root), "Deep", "Kicks", "Pads"].sorted())
        XCTAssertEqual(idx.totalSamples, 3)
        XCTAssertEqual(idx.files.map(\.name).sorted(), ["a.wav", "b.aif", "c.WAV"])

        let pads = idx.folders.first { $0.name == "Pads" }!
        XCTAssertEqual(pads.totalSamples, 1)
        XCTAssertEqual(pads.children.count, 1)
        // The bytes of a non-sample file count into the folder's weight.
        let deep = idx.folders.first { $0.name == "Deep" }!
        XCTAssertEqual(pads.totalBytes, deep.totalBytes + 5)
        // Weight-only folders pass their bytes up to the root without becoming nodes.
        let rootFolder = idx.folders[0]
        let onDisk = try! FileManager.default.subpathsOfDirectory(atPath: root)
            .reduce(Int64(0)) { sum, p in
                let a = try? FileManager.default.attributesOfItem(atPath: root + "/" + p)
                return sum + ((a?[.type] as? FileAttributeType) == .typeRegular ? (a?[.size] as? NSNumber)?.int64Value ?? 0 : 0)
            }
        // The AppleDouble file is hidden for the walk (not counted); everything else is.
        XCTAssertEqual(rootFolder.totalBytes, onDisk - 13)
        XCTAssertEqual(idx.location(of: idx.folders.firstIndex { $0.name == "Deep" }), "Pads/Deep")
        XCTAssertEqual(idx.location(of: 0), SampleIndex.norm(root))
        XCTAssertEqual(idx.location(of: nil), "")
    }

    func testSampleNameRules() {
        XCTAssertTrue(SampleIndex.isSampleName("kick.WAV"))
        XCTAssertTrue(SampleIndex.isSampleName("loop.rx2"))
        XCTAssertTrue(SampleIndex.isSampleName("x.aifc"))
        XCTAssertFalse(SampleIndex.isSampleName("._kick.wav"))
        XCTAssertFalse(SampleIndex.isSampleName(".wav"))
        XCTAssertFalse(SampleIndex.isSampleName("kick"))
        XCTAssertFalse(SampleIndex.isSampleName("notes.txt"))
        XCTAssertTrue(SampleIndex.canPreview("a.m4a"))
        XCTAssertFalse(SampleIndex.canPreview("a.ogg"))
        XCTAssertFalse(SampleIndex.canPreview("a.rx2"))
        XCTAssertTrue(SampleIndex.isWeightOnly("Ableton Folder Info"))
        XCTAssertTrue(SampleIndex.isWeightOnly("My Song Project"))
        XCTAssertTrue(SampleIndex.isWeightOnly("backup"))
        XCTAssertFalse(SampleIndex.isWeightOnly("Projects"))
    }

    func testEffectiveRootsDropNestedAndDisabled() {
        let roots = ["/a/Samples", "/a/Samples/Drums", "/a/Samples2", "/b/Loops", "/a/Samples/"]
        XCTAssertEqual(SampleIndex.effective(roots, disabled: []), ["/a/Samples", "/a/Samples2", "/b/Loops"])
        XCTAssertEqual(SampleIndex.effective(roots, disabled: ["/a/Samples"]),
                       ["/a/Samples/Drums", "/a/Samples2", "/b/Loops"])
        XCTAssertTrue(SampleIndex.inside("/a/Samples/x", "/a/Samples"))
        XCTAssertFalse(SampleIndex.inside("/a/Samples2", "/a/Samples"))
        XCTAssertFalse(SampleIndex.inside("/a/Samples", "/a/Samples"))
        XCTAssertTrue(SampleIndex.containsPath(["/A/samples/"], "/a/Samples"))
    }

    func testAiffThePreviewCannotPlayIsSilentAndRemembered() {
        let t = makeTemp("samples")
        let root = t.mkdir("Lib")
        SampleFixtures.put(SampleFixtures.aiff(compression: "able"), at: root + "/x/live.aif")
        SampleFixtures.put(SampleFixtures.aiff(compression: "sowt", seed: 9), at: root + "/x/mac.aif")
        SampleFixtures.put(SampleFixtures.aiff(seed: 8), at: root + "/x/plain.aiff")
        var idx = SampleIndex.build(roots: [root], disabled: [])
        func file(_ n: String, _ i: SampleIndex) -> SampleFile { i.files.first { $0.name == n }! }
        XCTAssertTrue(file("live.aif", idx).silent)
        XCTAssertFalse(file("live.aif", idx).canPreview)
        XCTAssertFalse(file("mac.aif", idx).silent)
        XCTAssertTrue(file("plain.aiff", idx).canPreview)

        // A rescan takes the flag from the previous index for an unchanged file (same path and
        // size) instead of opening it again: prove it by planting a wrong flag.
        let plain = idx.files.firstIndex { $0.name == "plain.aiff" }!
        idx.files[plain].silent = true
        let again = SampleIndex.build(roots: [root], disabled: [], previous: idx)
        XCTAssertTrue(file("plain.aiff", again).silent)
        // ...but a changed size is looked at anew.
        SampleFixtures.put(SampleFixtures.aiff(frames: 200, seed: 8), at: root + "/x/plain.aiff")
        let changed = SampleIndex.build(roots: [root], disabled: [], previous: idx)
        XCTAssertFalse(file("plain.aiff", changed).silent)
    }

    func testPrintsAreTakenOnlyForNameAndSizeCollisions() {
        let t = makeTemp("samples")
        let root = t.mkdir("Lib")
        SampleFixtures.put(SampleFixtures.wav(seed: 1), at: root + "/A/kick.wav")
        SampleFixtures.put(SampleFixtures.wav(seed: 1), at: root + "/B/kick.wav")       // a copy
        SampleFixtures.put(SampleFixtures.wav(seed: 2), at: root + "/C/kick.wav")       // Dry vs Wet
        SampleFixtures.put(SampleFixtures.wav(seed: 3), at: root + "/A/snare.wav")      // alone
        var idx = SampleIndex.build(roots: [root], disabled: [])
        func print(_ folder: String, _ name: String, _ i: SampleIndex) -> UInt64 {
            i.files.first { i.folders[$0.folder].name == folder && $0.name == name }!.print
        }
        XCTAssertNotEqual(print("A", "kick.wav", idx), 0)
        XCTAssertEqual(print("A", "kick.wav", idx), print("B", "kick.wav", idx))
        XCTAssertNotEqual(print("A", "kick.wav", idx), print("C", "kick.wav", idx))
        XCTAssertEqual(print("A", "snare.wav", idx), 0)

        // A print is kept while size and date are unchanged.
        for i in idx.files.indices where idx.files[i].print != 0 { idx.files[i].print = 7 }
        let again = SampleIndex.build(roots: [root], disabled: [], previous: idx)
        XCTAssertEqual(print("A", "kick.wav", again), 7)
        XCTAssertEqual(SamplePrints.print(path: root + "/nope.wav"), 0)
    }

    func testCacheRoundTripsAndIsByteStable() throws {
        let (t, root) = tree()
        let idx = SampleIndex.build(roots: [root], disabled: [])
        let dir = t.mkdir("data")
        SampleCache.save(idx, dir: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/samples.cache"))
        let back = SampleCache.load(dir: dir)
        XCTAssertEqual(back.roots, idx.roots)
        XCTAssertEqual(back.folders.map(\.path), idx.folders.map(\.path))
        XCTAssertEqual(back.folders.map(\.name), idx.folders.map(\.name))
        XCTAssertEqual(back.folders.map(\.parent), idx.folders.map(\.parent))
        XCTAssertEqual(back.folders.map(\.children), idx.folders.map(\.children))
        XCTAssertEqual(back.folders.map(\.files), idx.folders.map(\.files))
        XCTAssertEqual(back.folders.map(\.totalBytes), idx.folders.map(\.totalBytes))
        XCTAssertEqual(back.files.map(\.name), idx.files.map(\.name))
        XCTAssertEqual(back.files.map(\.size), idx.files.map(\.size))
        XCTAssertEqual(back.files.map(\.silent), idx.files.map(\.silent))
        for (a, b) in zip(back.files, idx.files) {
            XCTAssertEqual(a.modified?.timeIntervalSince1970 ?? 0, b.modified?.timeIntervalSince1970 ?? 0, accuracy: 1e-5)
        }
        XCTAssertEqual(SampleCache.encode(back), SampleCache.encode(SampleCache.load(dir: dir)))
    }

    func testCacheVersion2HasNoDatesAndGarbageIsIgnored() throws {
        var w = DotNetWriter()
        w.int32(2)
        w.int32(2)
        w.string("/lib"); w.int32(-1); w.int32(1); w.int64(300)
        w.string("/lib/Kicks"); w.int32(0); w.int32(1); w.int64(100)
        w.int32(1)
        w.int32(1); w.string("a.aif"); w.int64(100); w.bool(true)
        w.int32(1); w.int32(0)
        let idx = try SampleCache.decode(w.data)
        XCTAssertEqual(idx.folders[1].name, "Kicks")
        XCTAssertEqual(idx.folders[0].children, [1])
        XCTAssertTrue(idx.files[0].silent)
        XCTAssertNil(idx.files[0].modified)
        XCTAssertEqual(idx.path(of: 0), "/lib/Kicks/a.aif")

        var w9 = DotNetWriter()
        w9.int32(9)
        XCTAssertEqual(try SampleCache.decode(w9.data).folders.count, 0)
        XCTAssertThrowsError(try SampleCache.decode(Data([4, 0, 0, 0, 5, 0, 0, 0])))

        let t = makeTemp("samples")
        XCTAssertEqual(SampleCache.load(dir: t.path).folders.count, 0)
        t.write("samples.cache", "garbage")
        XCTAssertEqual(SampleCache.load(dir: t.path).folders.count, 0)
    }

    func testOnlyDropsSwitchedOffRootsAndKeepsTheRest() {
        let t = makeTemp("samples")
        let a = t.mkdir("A"), b = t.mkdir("B")
        SampleFixtures.put(SampleFixtures.wav(seed: 1), at: a + "/x/one.wav")
        SampleFixtures.put(SampleFixtures.wav(seed: 2), at: b + "/y/two.wav")
        SampleFixtures.put(SampleFixtures.wav(seed: 3), at: b + "/y/three.wav")
        let idx = SampleIndex.build(roots: [a, b], disabled: [])
        XCTAssertEqual(idx.roots.count, 2)
        XCTAssertEqual(idx.totalSamples, 3)

        XCTAssertEqual(idx.only([a, b], disabled: []).totalSamples, 3)
        let onlyB = idx.only([a, b], disabled: [a])
        XCTAssertEqual(onlyB.totalSamples, 2)
        XCTAssertEqual(onlyB.roots, [0])
        XCTAssertEqual(onlyB.files.map(\.name).sorted(), ["three.wav", "two.wav"])
        XCTAssertEqual(onlyB.path(of: 0).hasSuffix("/y/" + onlyB.files[0].name), true)
        XCTAssertEqual(onlyB.folders.map(\.parent), [nil, 0])
        XCTAssertEqual(idx.only([a], disabled: []).totalSamples, 1)
    }

    func testCountAgreesWithTheWalkAndUnreadableRootIsSkipped() {
        let (t, root) = tree()
        XCTAssertEqual(SampleIndex.countIn(root), 3)
        XCTAssertEqual(SampleIndex.countIn(t.sub("nowhere")), -1)
        let idx = SampleIndex.build(roots: [t.sub("nowhere"), root], disabled: [])
        XCTAssertEqual(idx.totalSamples, 3)
        XCTAssertEqual(idx.roots.count, 1)
    }

    func testCancelledWalkGivesNothingAndProgressIsReported() {
        let (_, root) = tree()
        XCTAssertEqual(SampleIndex.build(roots: [root], disabled: [], isCancelled: { true }).folders.count, 0)
        var last = 0
        let idx = SampleIndex.build(roots: [root], disabled: [], progress: { last = $0 })
        XCTAssertEqual(last, idx.totalSamples)
    }

    func testPackFolderAndWithin() {
        let (_, root) = tree()
        let idx = SampleIndex.build(roots: [root], disabled: [])
        let deep = idx.folders.firstIndex { $0.name == "Deep" }!
        let pads = idx.folders.firstIndex { $0.name == "Pads" }!
        XCTAssertEqual(idx.packFolder(of: deep), pads)
        XCTAssertEqual(idx.packFolder(of: pads), pads)
        XCTAssertTrue(idx.folder(deep, isWithin: 0))
        XCTAssertFalse(idx.folder(pads, isWithin: deep))
        XCTAssertEqual(SampleLister.ancestors(of: deep, in: idx),
                       [idx.folders[0].path.lowercased(), idx.folders[pads].path.lowercased(),
                        idx.folders[deep].path.lowercased()])
    }
}
