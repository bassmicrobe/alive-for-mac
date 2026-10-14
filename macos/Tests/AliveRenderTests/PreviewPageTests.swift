import XCTest
@testable import AliveCore
@testable import AliveRender

/// A synthetic set with the same XML shapes the core's own fixtures use.
enum SyntheticSet {
    static func clip(start: Double, end: Double, name: String, color: Int) -> String {
        "<AudioClip Id=\"3\" Time=\"\(start)\"><CurrentStart Value=\"\(start)\"/><CurrentEnd Value=\"\(end)\"/>"
            + "<Loop><LoopStart Value=\"0\"/><LoopEnd Value=\"\(end - start)\"/><StartRelative Value=\"0\"/>"
            + "<LoopOn Value=\"false\"/></Loop><Name Value=\"\(name)\"/><Color Value=\"\(color)\"/>"
            + "<Disabled Value=\"false\"/></AudioClip>"
    }

    static func track(_ kind: String, id: Int, name: String, extra: String = "") -> String {
        "<\(kind) Id=\"\(id)\"><Name><EffectiveName Value=\"\(name)\"/></Name><Color Value=\"14\"/>\(extra)</\(kind)>"
    }

    static func arranger(_ clips: String) -> String {
        "<DeviceChain><MainSequencer><Sample><ArrangerAutomation><Events>\(clips)</Events></ArrangerAutomation>"
            + "</Sample></MainSequencer></DeviceChain>"
    }

    static func vst3(name: String, browser: String) -> String {
        "<BrowserContentPath Value=\"\(browser)\"/><PluginDesc><Vst3PluginInfo Id=\"0\"><Name Value=\"\(name)\"/>"
            + "<Uid><Fields.0 Value=\"1\"/><Fields.1 Value=\"2\"/><Fields.2 Value=\"3\"/><Fields.3 Value=\"4\"/></Uid>"
            + "</Vst3PluginInfo></PluginDesc>"
    }

    static func sample(_ abs: String) -> String {
        "<SampleRef><FileRef><RelativePathType Value=\"1\"/><RelativePath Value=\"\(abs)\"/><Path Value=\"\(abs)\"/>"
            + "<Type Value=\"2\"/><LivePackName Value=\"\"/><LivePackId Value=\"\"/><OriginalFileSize Value=\"1000\"/>"
            + "</FileRef></SampleRef>"
    }

    /// 4 audio-ish tracks' worth of structure, 128 BPM, C Major, one plug-in with markup in its name.
    static func xml(title: String = "Set") -> String {
        let drums = track("AudioTrack", id: 1, name: "Drums",
                          extra: arranger(clip(start: 0, end: 64, name: "kick", color: 14)) + sample("/s/kick.wav") + sample("/s/hat.wav"))
        let bass = track("MidiTrack", id: 2, name: "Bass",
                         extra: vst3(name: "Serum &lt;2&gt; &amp; Co", browser: "query:Plugins#VST3:Xfer:Serum"))
        let group = track("GroupTrack", id: 3, name: "Group")
        let main = "<MainTrack Id=\"9\"><DeviceChain><Mixer><Tempo><LomId Value=\"0\"/><Manual Value=\"128\"/></Tempo></Mixer></DeviceChain></MainTrack>"
        let scale = "<ScaleInformation><Root Value=\"0\"/><Name Value=\"0\"/></ScaleInformation><PreferFlatRootNote Value=\"false\"/>"
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Ableton MajorVersion=\"5\" MinorVersion=\"12.0_12300\" Creator=\"Ableton Live 12.3.5\">"
            + "<LiveSet><Tracks>\(drums)\(bass)\(group)</Tracks>\(main)\(scale)</LiveSet></Ableton>"
    }

    static func model(name: String = "My Song", gz: Bool = false) -> PreviewModel {
        let data = Data(xml().utf8)
        return PreviewModel(path: "/Music/\(name) Project/\(name).als", fileSize: 12_345,
                            modified: Date(timeIntervalSince1970: 1_700_000_000),
                            info: AlsFile.parse(xml: data, path: "/Music/\(name).als"),
                            arrangement: Arrangement.parse(xml: data, path: "/Music/\(name).als"))
    }
}

final class PreviewPageTests: XCTestCase {
    func testPageShowsTheSetsFactsInEnglish() {
        let html = PreviewPage.html(SyntheticSet.model(), language: .en, pictureSource: "cid:arrangement.png")
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<h1>My Song</h1>"))
        XCTAssertTrue(html.contains("Ableton Live 12.3.5"))
        XCTAssertTrue(html.contains("128 <small>BPM</small>"))
        XCTAssertTrue(html.contains("C Major"))
        XCTAssertTrue(html.contains("<strong>3</strong>"))                     // tracks
        XCTAssertTrue(html.contains("1 audio · 1 MIDI · 1 group"))
        XCTAssertTrue(html.contains("0:30"))                                     // 64 beats at 128 BPM
        XCTAssertTrue(html.contains("<small>16 bars</small>"))
        XCTAssertTrue(html.contains("src=\"cid:arrangement.png\""))
        XCTAssertTrue(html.contains("/Music/My Song Project/My Song.als"))
        XCTAssertTrue(html.contains("<span>Samples</span> <strong>2</strong>"))
    }

    func testPageInJapanese() {
        let html = PreviewPage.html(SyntheticSet.model(), language: .ja, pictureSource: nil)
        XCTAssertTrue(html.contains("lang=\"ja\""))
        XCTAssertTrue(html.contains("テンポ"))
        XCTAssertTrue(html.contains("プラグイン"))
        XCTAssertTrue(html.contains("サンプル"))
        XCTAssertFalse(html.contains("<img"))                                    // no picture source, no image
    }

    func testPluginsAreListedWithoutAnyInstalledJudgementAndEscaped() {
        let html = PreviewPage.html(SyntheticSet.model(), language: .en, pictureSource: nil)
        XCTAssertTrue(html.contains("Serum &lt;2&gt; &amp; Co"))
        XCTAssertFalse(html.contains("Serum <2>"))
        XCTAssertTrue(html.contains("<b>VST3</b>"))
        XCTAssertTrue(html.contains("<i>Xfer</i>"))
        let lower = html.lowercased()
        XCTAssertFalse(lower.contains("missing"))
        XCTAssertFalse(lower.contains("installed"))
    }

    func testFileNameWithMarkupIsEscaped() {
        var model = SyntheticSet.model()
        model.path = "/x/<script>alert(1)</script>.als"
        let html = PreviewPage.html(model, language: .en, pictureSource: nil)
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testLongPluginListIsSummarised() {
        var model = SyntheticSet.model()
        model.info.plugins = (0..<50).map { i in
            var p = PluginRef(kind: .vst3)
            p.name = String(format: "Plug %02d", i)
            return p
        }
        let html = PreviewPage.html(model, language: .en, pictureSource: nil)
        XCTAssertTrue(html.contains("Plug 00"))
        XCTAssertFalse(html.contains("Plug 49"))
        XCTAssertTrue(html.contains("+14 more"))
    }

    func testUnreadableSetStillRendersWithAWarning() {
        let model = PreviewModel.load(path: "/nonexistent/none.als")
        let html = PreviewPage.html(model, language: .en, pictureSource: nil)
        XCTAssertTrue(html.contains("<h1>none</h1>"))
        XCTAssertTrue(html.contains("could not be read"))
    }

    func testLoadReadsAFileFromDisk() throws {
        let dir = NSTemporaryDirectory() + "alive-ql-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/Disk Song.als"
        try Gzip.compress(Data(SyntheticSet.xml().utf8)).write(to: URL(fileURLWithPath: path))

        let model = PreviewModel.load(path: path)
        XCTAssertNil(model.info.error)
        XCTAssertEqual(model.name, "Disk Song")
        XCTAssertEqual(model.info.totalTracks, 3)
        XCTAssertEqual(model.arrangement.clipCount, 1)
        XCTAssertGreaterThan(model.fileSize, 0)
        XCTAssertNotNil(model.modified)
    }

    func testPictureIsAPngOfTheArrangement() throws {
        let data = try XCTUnwrap(PreviewPage.pictureData(for: SyntheticSet.model().arrangement, width: 600))
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertNil(PreviewPage.pictureData(for: Arrangement()))
    }

    func testNumberFormatting() {
        XCTAssertEqual(PreviewPage.number(128), "128")
        XCTAssertEqual(PreviewPage.number(127.5), "127.5")
        XCTAssertEqual(PreviewPage.number(120.25), "120.25")
    }

    func testLanguageChoiceFollowsFirstPreferredLanguage() {
        XCTAssertEqual(PreviewLanguage.system(preferred: ["ja-JP", "en-US"]), .ja)
        XCTAssertEqual(PreviewLanguage.system(preferred: ["en-US", "ja-JP"]), .en)
        XCTAssertEqual(PreviewLanguage.system(preferred: []), .en)
    }

    func testEveryStringHasBothLanguages() {
        for s in PreviewString.allCases {
            XCTAssertFalse(s.text(.en).isEmpty, "\(s) en")
            XCTAssertFalse(s.text(.ja).isEmpty, "\(s) ja")
        }
    }
}
