import AppKit
import XCTest
@testable import AliveCore
@testable import AliveUI

/// Upstream a6c8dc1 / 9ce4b4b in the full-screen preview: a canvas that tells the header its limits and
/// never keeps the last set's view. (The caption in the set's own bars: ArrangementPreviewTests.)
@MainActor
final class PlayerPreviewUpstream133Tests: XCTestCase {
    /// The main run loop gets a turn: the canvas reports after the layout pass, not during it.
    private func letTheCanvasReport() async throws {
        try await Task.sleep(nanoseconds: 60_000_000)
    }

    func testCanvasReportsItsLimitsOnceSizedAndStartsAnotherSetFromTheFittedView() async throws {
        let control = PreviewCanvasControl()
        // As SwiftUI builds it: the set arrives before the first layout gives the canvas a size.
        let canvas = ArrangementCanvasView(frame: .zero)
        canvas.control = control
        control.canvas = canvas
        canvas.show(SyntheticArrangement.make(), path: "/p/one.als")
        XCTAssertEqual(control.maxZoom, .infinity, "unknown yet: zooming in is not held back")

        canvas.setFrameSize(NSSize(width: 900, height: 500))
        try await letTheCanvasReport()
        XCTAssertGreaterThan(control.maxZoom, 2)
        XCTAssertLessThan(control.maxZoom, .infinity)
        XCTAssertTrue(control.isAtFit)

        control.zoomIn()
        XCTAssertEqual(control.zoom, 2, accuracy: 0.01)
        XCTAssertFalse(control.isAtFit)

        canvas.show(SyntheticArrangement.make(), path: "/p/two.als")
        XCTAssertEqual(control.zoom, 1, accuracy: 0.001, "the next set is not left zoomed like the last")
        XCTAssertTrue(control.isAtFit)

        canvas.setFrameSize(NSSize(width: 1100, height: 700))
        try await letTheCanvasReport()
        XCTAssertTrue(control.isAtFit, "a resize alone is not a change of the view")
    }
}
