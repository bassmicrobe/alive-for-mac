import AppKit
import XCTest
@testable import AliveCore
@testable import AliveUI

/// Upstream a6c8dc1 / 9ce4b4b in the full-screen preview: the caption in the set's own bars with
/// singular forms, and a canvas that never keeps the last set's view.
@MainActor
final class PlayerPreviewUpstream133Tests: XCTestCase {
    func testCaptionCountsBarsInTheSetsTimeSignatureAndUsesSingularForms() {
        Localizer.shared.preference = .en
        defer { Localizer.shared.preference = .system }
        var a = SyntheticArrangement.make()
        a.tempo = 0
        a.barBeats = 3                                   // 3/4: 32 beats are 11 bars, not 8
        a.tracks = [a.tracks[0]]
        a.clipCount = 1
        XCTAssertEqual(PreviewSizing.metrics(path: "/p/a.als", key: "", arrangement: a), "11 bars   ·   1 track   ·   1 clip")
        a.end = 3
        XCTAssertTrue(PreviewSizing.metrics(path: "/p/a.als", key: "", arrangement: a).hasPrefix("1 bar   ·"))
    }

    func testNavigationStringsAreComplete() {
        assertStringTableIsComplete(PreviewNavStrings.self)
    }

    func testCanvasStartsAnotherSetFromTheFittedView() {
        let control = PreviewCanvasControl()
        let canvas = ArrangementCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        canvas.control = control
        control.canvas = canvas
        canvas.show(SyntheticArrangement.make(), path: "/p/one.als")
        control.zoomIn()
        XCTAssertEqual(control.zoom, 2, accuracy: 0.01)
        XCTAssertFalse(control.isAtFit)

        canvas.show(SyntheticArrangement.make(), path: "/p/two.als")
        XCTAssertEqual(control.zoom, 1, accuracy: 0.001, "the next set is not left zoomed like the last")
        XCTAssertTrue(control.isAtFit)
    }
}
