import XCTest
@testable import AliveCore

/// Upstream a6c8dc1: bars are counted in the set's time signature.
final class ArrangementUpstream133Tests: XCTestCase {
    /// Live writes the meter as 99 * log2(denominator) + numerator - 1.
    func testMeterCodesDecodeToBeatsPerBar() {
        XCTAssertEqual(ArrangementParser.meter(201), 4)        // 4/4
        XCTAssertEqual(ArrangementParser.meter(200), 3)        // 3/4
        XCTAssertEqual(ArrangementParser.meter(302), 3)        // 6/8
        XCTAssertEqual(ArrangementParser.meter(303), 3.5)      // 7/8
        XCTAssertEqual(ArrangementParser.meter(-1), 4)         // does not decode: 4/4
        XCTAssertEqual(ArrangementParser.meter(99 * 6), 4)     // a denominator of 64 or more
    }

    /// The set's meter is the main track's. A clip carries a TimeSignature of its own, and it
    /// sits in an audio track that comes first in the file.
    func testBarsFollowTheMainTracksMeterNotAClips() throws {
        let clip = "<AudioClip Id=\"1\"><CurrentStart Value=\"0\"/><CurrentEnd Value=\"16\"/>"
            + "<TimeSignature><TimeSignatures><RemoteableTimeSignature><Numerator Value=\"7\"/></RemoteableTimeSignature>"
            + "</TimeSignatures><Manual Value=\"303\"/></TimeSignature></AudioClip>"
        let track = "<AudioTrack Id=\"1\"><Name><EffectiveName Value=\"A\"/></Name><DeviceChain><MainSequencer><Sample>"
            + "<ArrangerAutomation><Events>\(clip)</Events></ArrangerAutomation></Sample></MainSequencer></DeviceChain></AudioTrack>"
        let main = "<MainTrack Id=\"9\"><DeviceChain><Mixer><Tempo><LomId Value=\"0\"/><Manual Value=\"120\"/></Tempo>"
            + "<TimeSignature><LomId Value=\"0\"/><Manual Value=\"200\"/></TimeSignature></Mixer></DeviceChain></MainTrack>"

        let a = Arrangement.parse(xml: Data(Fx.als(live: Fx.tracks(track) + main).utf8))
        XCTAssertNil(a.error)
        XCTAssertEqual(a.clipCount, 1)
        XCTAssertEqual(a.barBeats, 3)
        XCTAssertEqual(a.bars, 6)                              // 16 beats in 3/4, not 4 bars of 4/4

        let plain = Arrangement.parse(xml: Data(Fx.als(live: Fx.tracks(track) + Fx.main(tempo: 120)).utf8))
        XCTAssertEqual(plain.barBeats, 4, "a set with no meter keeps 4/4")
        XCTAssertEqual(plain.bars, 4)
    }
}
