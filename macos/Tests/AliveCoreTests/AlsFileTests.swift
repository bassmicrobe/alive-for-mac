import XCTest
@testable import AliveCore

final class GzipTests: XCTestCase {
    func testRoundTrip() throws {
        let original = Data(String(repeating: "<a Value=\"1\"/>", count: 50_000).utf8)
        let gz = try Gzip.compress(original, level: 9)
        XCTAssertTrue(Gzip.isGzip(gz))
        XCTAssertLessThan(gz.count, original.count / 10)
        XCTAssertEqual(try Gzip.decompress(gz), original)
    }

    func testEmptyInputRoundTrips() throws {
        XCTAssertEqual(try Gzip.decompress(try Gzip.compress(Data())), Data())
    }

    func testCorruptAndTruncatedThrow() throws {
        XCTAssertThrowsError(try Gzip.decompress(Data([0x1F, 0x8B, 0x00, 0x01, 0x02])))
        let gz = try Gzip.compress(Data(String(repeating: "abcdef", count: 10_000).utf8))
        XCTAssertThrowsError(try Gzip.decompress(gz.prefix(gz.count / 2)))
    }

    func testIsGzip() {
        XCTAssertFalse(Gzip.isGzip(Data("<xml/>".utf8)))
        XCTAssertFalse(Gzip.isGzip(Data()))
    }

    func testPlainXmlFallbackWhenReadingFile() throws {
        let t = makeTemp()
        let p = t.write("plain.als", Fx.simpleSet(tempo: 99))
        let info = AlsFile.read(path: p)
        XCTAssertNil(info.error)
        XCTAssertEqual(info.tempo, 99)
    }

    func testMissingFileReportsError() {
        let info = AlsFile.read(path: "/nonexistent/none.als")
        XCTAssertNotNil(info.error)
    }
}

final class AlsFileTests: XCTestCase {
    private func parse(_ live: String, creator: String = "Ableton Live 12.3.5") -> AlsInfo {
        AlsFile.parse(xml: Data(Fx.als(creator: creator, live: live).utf8))
    }

    func testCreatorTracksTempoAndKey() {
        let info = AlsFile.parse(xml: Data(Fx.simpleSet(tempo: 128).utf8))
        XCTAssertNil(info.error)
        XCTAssertEqual(info.creator, "Ableton Live 12.3.5")
        XCTAssertEqual(info.tempo, 128)
        XCTAssertEqual(info.audioTracks, 1)
        XCTAssertEqual(info.midiTracks, 1)
        XCTAssertEqual(info.groupTracks, 1)
        XCTAssertEqual(info.totalTracks, 3)
        XCTAssertEqual(info.key, "C Minor")
        XCTAssertFalse(info.preferFlat)
    }

    func testTempoComesFromMainTrackNotClips() {
        let clipTempo = "<AudioClip><Tempo><Manual Value=\"99\"/></Tempo></AudioClip>"
        let live = Fx.tracks(Fx.track("AudioTrack", extra: clipTempo)) + Fx.main(tempo: 140)
        XCTAssertEqual(parse(live).tempo, 140)
    }

    func testMasterTrackNameBeforeLive12() {
        let live = Fx.tracks(Fx.track("AudioTrack")) + Fx.main(tag: "MasterTrack", tempo: 90)
        XCTAssertEqual(parse(live, creator: "Ableton Live 10.1.41").tempo, 90)
    }

    func testNoMainTrackMeansNoTempo() {
        XCTAssertEqual(parse(Fx.tracks(Fx.track("AudioTrack"))).tempo, 0)
    }

    func testKeyOnClipsIsIgnoredAndFlatSpelling() {
        let clipScale = Fx.tracks(Fx.track("AudioTrack", extra: "<AudioClip>" + Fx.scale(root: 5, name: 3) + "</AudioClip>"))
        let info = parse(clipScale + Fx.scale(root: 1, name: 0, flat: true))
        XCTAssertEqual(info.scaleRoot, 1)
        XCTAssertEqual(info.key, "Db Major")
        XCTAssertTrue(info.preferFlat)
    }

    func testNoKeyInOlderSets() {
        let info = parse(Fx.tracks(Fx.track("AudioTrack")))
        XCTAssertEqual(info.scaleRoot, -1)
        XCTAssertEqual(info.key, "")
    }

    func testVst3NameUidAndEmptyNameTrap() throws {
        let plug = Fx.vst3(name: "FabFilter Pro-Q 4",
                           fields: [-313016974, 1549813374, -1504849164, 7703407],
                           browser: "query:Plugins#VST3:FabFilter:Pro-Q%204")
        let info = parse(Fx.tracks(Fx.track("AudioTrack", extra: plug)))
        let p = try XCTUnwrap(info.plugins.first)
        XCTAssertEqual(info.plugins.count, 1)
        XCTAssertEqual(p.kind, .vst3)
        XCTAssertEqual(p.name, "FabFilter Pro-Q 4")                    // not the nested empty <Name>
        XCTAssertEqual(p.uid, "vst3:ed57bd72-5c60-467e-a64d-d2f400758b6f")
        XCTAssertEqual(p.manufacturer, "FabFilter")
        XCTAssertTrue(p.vendorConfident)
    }

    func testVst2NameUidAndFolderVendorIsNotConfident() throws {
        let plug = Fx.vst2(name: "Addictive Drums 2", uniqueId: 2017543218, browser: "query:Plugins#VST:Gen:Addictive%20Drums%202")
        let p = try XCTUnwrap(parse(Fx.tracks(Fx.track("AudioTrack", extra: plug))).plugins.first)
        XCTAssertEqual(p.kind, .vst2)
        XCTAssertEqual(p.uid, "vst2:2017543218")
        XCTAssertEqual(p.manufacturer, "Gen")
        XCTAssertFalse(p.vendorConfident)
    }

    func testAudioUnitFourCCUidAndVendor() throws {
        // Codes from a real Pioneer RMX-1000 set: 'aumf' / '<sub>' / 'Pion'.
        let plug = Fx.au(name: "RMX-1000 Plug-in", vendor: "Pioneer Corporation",
                         type: 1635085670, sub: 909342512, mfr: 1349087086)
        let p = try XCTUnwrap(parse(Fx.tracks(Fx.track("AudioTrack", extra: plug))).plugins.first)
        XCTAssertEqual(p.kind, .audioUnit)
        XCTAssertEqual(p.name, "RMX-1000 Plug-in")
        XCTAssertEqual(p.manufacturer, "Pioneer Corporation")
        XCTAssertTrue(p.vendorConfident)
        XCTAssertEqual(p.uid, "au:aumf:" + AlsFile.fourCC(909342512) + ":Pion")
        XCTAssertEqual(AlsFile.fourCC(1635085670), "aumf")
        XCTAssertEqual(AlsFile.fourCC(1349087086), "Pion")
    }

    func testFourCCNonPrintableFallsBackToDecimal() {
        XCTAssertEqual(AlsFile.fourCC(5), "5")
        XCTAssertEqual(AlsFile.fourCC(UInt32(bitPattern: -1)), "4294967295")
    }

    func testAuWithNegativeSignedComponentValues() throws {
        // 0xFFFFFFFF as a signed int is -1; the uid must still be built from the unsigned bits.
        let plug = Fx.au(name: "X", vendor: "V", type: 1635085670, sub: -1, mfr: 1349087086)
        let p = try XCTUnwrap(parse(Fx.tracks(Fx.track("AudioTrack", extra: plug))).plugins.first)
        XCTAssertEqual(p.uid, "au:aumf:4294967295:Pion")
    }

    func testBrowserPathVendorFeedsNextPluginOnly() throws {
        let a = Fx.vst3(name: "A", fields: [1, 2, 3, 4], browser: "view:X-Plugins#Antares:Auto-Tune%20Pro")
        let b = Fx.vst3(name: "B", fields: [5, 6, 7, 8])
        let info = parse(Fx.tracks(Fx.track("AudioTrack", extra: a + b)))
        XCTAssertEqual(info.plugins.map(\.manufacturer), ["Antares", ""])
        XCTAssertEqual(info.plugins.map(\.vendorConfident), [false, false])
    }

    func testBuiltInDeviceBrowserPathIgnored() {
        XCTAssertNil(AlsFile.parseBrowserPath("query:Everything#Reverb"))
        XCTAssertNil(AlsFile.parseBrowserPath(""))
        XCTAssertNil(AlsFile.parseBrowserPath(nil))
        XCTAssertNil(AlsFile.parseBrowserPath("query:Plugins#"))
        XCTAssertEqual(AlsFile.parseBrowserPath("view:X-Plugins#Decapitator")?.manufacturer, nil)
        XCTAssertEqual(AlsFile.parseBrowserPath("query:Plugins#AU:Apple:AUDelay")?.confident, true)
    }

    func testFileRefsAndSampleDependencyRule() throws {
        let sample = Fx.fileRef(rel: "../../x.wav", abs: "/Users/me/x.wav", type: 1, size: 24201260)
        let preset = Fx.fileRef(parent: "FilePresetRef", rel: "p.adg", abs: "C:/other/p.adg", type: 0)
        let info = parse(Fx.tracks(Fx.track("AudioTrack", extra: sample + preset)))
        XCTAssertEqual(info.files.count, 2)
        let s = info.files[0]
        XCTAssertEqual(s.relativePath, "../../x.wav")
        XCTAssertEqual(s.absolutePath, "/Users/me/x.wav")
        XCTAssertEqual(s.relativePathType, 1)
        XCTAssertEqual(s.originalFileSize, 24201260)
        XCTAssertTrue(s.isSampleDependency)
        XCTAssertEqual(s.pathExtension, ".wav")
        XCTAssertFalse(info.files[1].isSampleDependency)
        XCTAssertEqual(info.files[1].container, "FilePresetRef")
    }

    func testMaxForLivePatchRefIsProvenanceNotDependency() {
        let m4l = Fx.fileRef(parent: "MxPatchRef", rel: "Devices/x.amxd", abs: "/a/x.amxd", type: 7)
        let info = parse(Fx.tracks(Fx.track("MidiTrack", extra: "<MxDeviceMidiEffect Id=\"0\">\(m4l)</MxDeviceMidiEffect>")))
        XCTAssertEqual(info.plugins.count, 0)
        XCTAssertEqual(info.files.count, 1)
        XCTAssertFalse(info.files[0].isSampleDependency)
        XCTAssertEqual(info.files[0].pathExtension, ".amxd")
    }

    func testWindowsStylePathsKeepTheirExtension() {
        var f = FileRefInfo()
        f.absolutePath = "C:\\Users\\x\\Loop.WAV"
        XCTAssertEqual(f.pathExtension, ".wav")
        XCTAssertEqual(FileRefInfo().pathExtension, "")
    }

    func testPluginRefKeyAndEmptyElements() {
        var p = PluginRef(kind: .vst3)
        p.name = "Serum"
        XCTAssertEqual(p.key, "Vst3|serum")
        // An empty FileRef and an empty plugin node add nothing.
        let info = parse(Fx.tracks(Fx.track("AudioTrack", extra: "<SampleRef><FileRef/></SampleRef><PluginDesc><VstPluginInfo/></PluginDesc>")))
        XCTAssertEqual(info.files.count, 0)
        XCTAssertEqual(info.plugins.count, 0)
    }

    func testTruncatedXmlKeepsPartialResultAndSetsError() {
        let xml = Fx.simpleSet(tempo: 120)
        let cut = String(xml.prefix(xml.count - 60))
        let info = AlsFile.parse(xml: Data(cut.utf8))
        XCTAssertNotNil(info.error)
        XCTAssertEqual(info.audioTracks, 1)
    }

    func testReadsGzippedFileFromDisk() {
        let t = makeTemp()
        let p = t.als("a/set.als", Fx.simpleSet(tempo: 101))
        let info = AlsFile.read(path: p)
        XCTAssertEqual(info.path, p)
        XCTAssertEqual(info.tempo, 101)
    }
}

final class ScalesTests: XCTestCase {
    func testNamesAndFormat() {
        XCTAssertEqual(Scales.scaleCount, 35)
        XCTAssertEqual(Scales.scaleName(0), "Major")
        XCTAssertEqual(Scales.scaleName(34), "Messiaen 7")
        XCTAssertEqual(Scales.scaleName(35), "")
        XCTAssertEqual(Scales.rootName(1, preferFlat: false), "C#")
        XCTAssertEqual(Scales.rootName(1, preferFlat: true), "Db")
        XCTAssertEqual(Scales.rootName(12, preferFlat: false), "")
        XCTAssertEqual(Scales.format(root: 9, scaleIndex: 1, preferFlat: false), "A Minor")
        XCTAssertEqual(Scales.format(root: 9, scaleIndex: 99, preferFlat: false), "A")
        XCTAssertEqual(Scales.format(root: -1, scaleIndex: 1, preferFlat: false), "")
        XCTAssertEqual(Scales.rootChoices.count, 12)
    }
}

final class LiveColorsTests: XCTestCase {
    func testPalette() {
        XCTAssertEqual(LiveColors.get(0), RGBColor(hex: 0xFD95A7))
        XCTAssertEqual(LiveColors.get(69), RGBColor(hex: 0x3C3C3C))
        XCTAssertEqual(LiveColors.get(70), LiveColors.fallback)
        XCTAssertEqual(LiveColors.get(-1), LiveColors.fallback)
        XCTAssertEqual(RGBColor(hex: 0x123456).hex, 0x123456)
    }
}
