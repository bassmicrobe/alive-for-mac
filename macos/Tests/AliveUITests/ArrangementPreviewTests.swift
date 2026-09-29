import XCTest
@testable import AliveCore
@testable import AliveUI

final class ArrangementPreviewTests: XCTestCase {
    func testFitPlanUsesTheViewportAndRetinaScale() {
        let plan = PreviewSizing.plan(view: CGSize(width: 1000, height: 600), zoomIndex: 0, trackCount: 10, taller: false, backingScale: 2)
        XCTAssertEqual(plan.points, CGSize(width: 1000, height: 600))
        XCTAssertEqual(plan.scale, 2)
        XCTAssertEqual(plan.pixelWidth, 2000)
        XCTAssertEqual(plan.pixelHeight, 1200)
    }

    func testZoomWidensThePictureAndDropsScaleBeforeExceedingTheLimits() {
        let x8 = PreviewSizing.plan(view: CGSize(width: 1000, height: 600), zoomIndex: 3, trackCount: 10, taller: false, backingScale: 2)
        XCTAssertEqual(x8.points.width, 8000)
        XCTAssertEqual(x8.scale, 2, "8000 pt at 2x is exactly the limit")
        let x16 = PreviewSizing.plan(view: CGSize(width: 1000, height: 600), zoomIndex: 4, trackCount: 10, taller: false, backingScale: 2)
        XCTAssertEqual(x16.points.width, 16000)
        XCTAssertEqual(x16.scale, 1, "16 000 pt at 2x would be 32 000 px")
        XCTAssertLessThanOrEqual(x16.pixelWidth, PreviewSizing.maxPixelWidth)
        let x32 = PreviewSizing.plan(view: CGSize(width: 1000, height: 600), zoomIndex: 5, trackCount: 10, taller: false, backingScale: 2)
        XCTAssertLessThanOrEqual(x32.points.width, Double(PreviewSizing.maxPixelWidth))
        XCTAssertLessThanOrEqual(x32.pixelWidth * x32.pixelHeight, PreviewSizing.maxPixels)
    }

    func testOutOfRangeZoomIsClamped() {
        let low = PreviewSizing.plan(view: CGSize(width: 500, height: 300), zoomIndex: -4, trackCount: 1, taller: false, backingScale: 1)
        let high = PreviewSizing.plan(view: CGSize(width: 500, height: 300), zoomIndex: 99, trackCount: 1, taller: false, backingScale: 1)
        XCTAssertEqual(low.points.width, 500)
        XCTAssertEqual(high.points.width, 500 * 32)
    }

    func testTallerTracksGrowTheHeightOnlyWhenNeeded() {
        let many = PreviewSizing.plan(view: CGSize(width: 1000, height: 400), zoomIndex: 0, trackCount: 80, taller: true, backingScale: 1)
        XCTAssertGreaterThan(many.points.height, 400)
        let few = PreviewSizing.plan(view: CGSize(width: 1000, height: 400), zoomIndex: 0, trackCount: 3, taller: true, backingScale: 1)
        XCTAssertEqual(few.points.height, 400)
    }

    func testSubtitleLine() {
        Localizer.shared.preference = .en
        defer { Localizer.shared.preference = .system }
        XCTAssertEqual(PreviewSizing.subtitle(directory: "/p/Song", key: "F# Minor", arrangement: nil), "/p/Song   ·   Reading the set…")

        var a = SyntheticArrangement.make()
        a.tempo = 127.5
        XCTAssertEqual(PreviewSizing.subtitle(directory: "/p/Song", key: "F# Minor", arrangement: a),
                       "/p/Song   ·   127.5 BPM   ·   F# Minor   ·   8 bars   ·   3 tracks   ·   3 clips")
        a.tempo = 0
        XCTAssertFalse(PreviewSizing.subtitle(directory: "/p", key: "C Major", arrangement: a).contains("C Major"))
        a.error = "not a set"
        XCTAssertEqual(PreviewSizing.subtitle(directory: "/p", key: "", arrangement: a), "/p   ·   not a set")
    }

    func testTempoText() {
        XCTAssertEqual(PreviewSizing.tempoText(150), "150")
        XCTAssertEqual(PreviewSizing.tempoText(127.5), "127.5")
        XCTAssertEqual(PreviewSizing.tempoText(127.35), "127.35")
        XCTAssertEqual(PreviewSizing.tempoText(90.001), "90")
    }
}
