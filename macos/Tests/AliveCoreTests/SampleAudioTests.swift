import XCTest
@testable import AliveCore

final class SampleAudioTests: XCTestCase {
    func testAiffHeaderReadsFormatAndDuration() throws {
        let t = makeTemp("audio")
        for rate in [44100, 48000, 96000, 22050, 8000] {
            let p = SampleFixtures.put(SampleFixtures.aiff(frames: rate / 2, rate: rate, channels: 2, bits: 24), at: t.sub("r\(rate).aif"))
            let h = try XCTUnwrap(AiffReader.readHeader(path: p))
            XCTAssertEqual(h.rate, rate)
            XCTAssertEqual(h.channels, 2)
            XCTAssertEqual(h.bits, 24)
            XCTAssertEqual(h.frames, Int64(rate / 2))
            XCTAssertEqual(h.durationMs, 500)
            XCTAssertEqual(h.compression, "NONE")
            XCTAssertTrue(AiffReader.canRead(path: p))
        }
    }

    func testAifcCompressionDecidesWhetherItCanBePlayed() throws {
        let t = makeTemp("audio")
        let sowt = SampleFixtures.put(SampleFixtures.aiff(compression: "sowt"), at: t.sub("a.aif"))
        let able = SampleFixtures.put(SampleFixtures.aiff(compression: "able"), at: t.sub("b.aif"))
        let fl32 = SampleFixtures.put(SampleFixtures.aiff(bits: 32, compression: "fl32"), at: t.sub("c.aifc"))
        let odd = SampleFixtures.put(SampleFixtures.aiff(bits: 12), at: t.sub("d.aif"))
        XCTAssertEqual(try XCTUnwrap(AiffReader.readHeader(path: sowt)).compression, "sowt")
        XCTAssertTrue(AiffReader.canRead(path: sowt))
        XCTAssertEqual(try XCTUnwrap(AiffReader.readHeader(path: able)).compression, "able")
        XCTAssertFalse(AiffReader.canRead(path: able))
        XCTAssertTrue(AiffReader.canRead(path: fl32))
        XCTAssertFalse(AiffReader.canRead(path: odd))
    }

    func testBrokenAiffIsNilNotACrash() {
        let t = makeTemp("audio")
        let good = SampleFixtures.aiff()
        XCTAssertNil(AiffReader.readHeader(path: t.sub("missing.aif")))
        XCTAssertNil(AiffReader.readHeader(path: SampleFixtures.put(Data("nope".utf8), at: t.sub("short.aif"))))
        XCTAssertNil(AiffReader.readHeader(path: SampleFixtures.put(Data("FORM".utf8 + [0, 0, 0, 4] + "WAVE".utf8), at: t.sub("form.aif"))))
        // Cut before SSND: no sound data, so nothing to play.
        XCTAssertNil(AiffReader.readHeader(path: SampleFixtures.put(good.prefix(12 + 8 + 18), at: t.sub("cut.aif"))))
        XCTAssertFalse(AiffReader.canRead(path: t.sub("missing.aif")))
        XCTAssertTrue(AiffReader.isAiffName("X.AIFC"))
        XCTAssertFalse(AiffReader.isAiffName("x.wav"))
    }

    func testWavHeaderReadsFormatAndDuration() throws {
        let t = makeTemp("audio")
        let p = SampleFixtures.put(SampleFixtures.wav(frames: 22050, rate: 44100, channels: 2, bits: 16), at: t.sub("a.wav"))
        let h = try XCTUnwrap(RiffReader.readHeader(path: p))
        XCTAssertEqual([h.rate, h.channels, h.bits], [44100, 2, 16])
        XCTAssertEqual(h.frames, 22050)
        XCTAssertEqual(h.durationMs, 500)
        XCTAssertEqual(try XCTUnwrap(AudioFileInfo.header(path: p)), h)
        XCTAssertNil(AudioFileInfo.header(path: SampleFixtures.put(Data("x".utf8), at: t.sub("a.mp3"))))
        XCTAssertNil(RiffReader.readHeader(path: SampleFixtures.put(Data("RIFFxxxxWAVE".utf8), at: t.sub("b.wav"))))
        XCTAssertNil(RiffReader.readHeader(path: t.sub("missing.wav")))
    }

    func testWavCutShortCountsTheBytesThatAreThere() throws {
        let t = makeTemp("audio")
        let whole = SampleFixtures.wav(frames: 100, rate: 8000, channels: 1, bits: 16)
        let p = SampleFixtures.put(whole.prefix(whole.count - 100), at: t.sub("cut.wav"))     // 50 frames lost
        XCTAssertEqual(try XCTUnwrap(RiffReader.readHeader(path: p)).frames, 50)
    }
}
