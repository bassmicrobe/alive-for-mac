import XCTest
@testable import AliveCore
@testable import AliveUI

final class ArrangementPreviewTests: XCTestCase {
    func testMetricsLine() {
        Localizer.shared.preference = .en
        defer { Localizer.shared.preference = .system }
        XCTAssertEqual(PreviewSizing.metrics(path: "/p/Song/a.als", key: "F# Minor", arrangement: nil), "Reading the set…")

        var a = SyntheticArrangement.make()
        a.tempo = 127.5
        // The folder is not part of it: a long path can never push the tempo out through truncation.
        XCTAssertEqual(PreviewSizing.metrics(path: "/p/Song/a.als", key: "F# Minor", arrangement: a),
                       "127.5 BPM   ·   F# Minor   ·   8 bars   ·   3 tracks   ·   3 clips")
        a.tempo = 0
        XCTAssertFalse(PreviewSizing.metrics(path: "/p/a.als", key: "C Major", arrangement: a).contains("C Major"))
        // Bars are counted in the set's own time signature, and one of anything has a form of its own.
        a.barBeats = 3                                   // 3/4: 32 beats are 11 bars, not 8
        a.tracks = [a.tracks[0]]
        a.clipCount = 1
        XCTAssertEqual(PreviewSizing.metrics(path: "/p/a.als", key: "", arrangement: a), "11 bars   ·   1 track   ·   1 clip")
        a.end = 3
        XCTAssertTrue(PreviewSizing.metrics(path: "/p/a.als", key: "", arrangement: a).hasPrefix("1 bar   ·"))
        // A raw parser error is not shown: the plain sentence is, in the UI language.
        a.error = "not a set"
        XCTAssertEqual(PreviewSizing.metrics(path: "/p/a.als", key: "", arrangement: a), CommonStrings.setReadFailed.s)
    }

    func testTempoText() {
        XCTAssertEqual(PreviewSizing.tempoText(150), "150")
        XCTAssertEqual(PreviewSizing.tempoText(127.5), "127.5")
        XCTAssertEqual(PreviewSizing.tempoText(127.35), "127.35")
        XCTAssertEqual(PreviewSizing.tempoText(90.001), "90")
    }
}
