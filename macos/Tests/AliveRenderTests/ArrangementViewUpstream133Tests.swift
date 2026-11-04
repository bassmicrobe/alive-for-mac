import CoreGraphics
import XCTest
@testable import AliveCore
@testable import AliveRender

/// The full-screen preview's view (upstream a6c8dc1): bars in the set's time signature, tracks that
/// scroll instead of squeezing, and the Live-like wheel. All in pixels, no window.
final class ArrangementViewUpstream133Tests: XCTestCase {
    private let options = RenderOptions.preview(scale: 1)

    private func space(tracks: Int, end: Double = 64, width: CGFloat = 1000, height: CGFloat = 300) -> ArrangementSpace {
        ArrangementSpace(area: CGRect(x: 0, y: 0, width: width, height: height), trackCount: tracks, end: end, options: options)
    }

    private func wheel(_ dy: Double, dx: Double = 0, shift: Bool = false, command: Bool = false, option: Bool = false) -> ArrangementScroll {
        ArrangementScroll(dx: dx, dy: dy, precise: false, shift: shift, command: command, option: option)
    }

    func testRulerAndGridCountBarsInTheSetsTimeSignature() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 300)
        // 3/4 at 10 px a beat: bar lines every 6 beats (two bars, to stay 56 px apart).
        let threeFour = ArrangementRender.rulerMarks(area: area, plot: area, options, end: 40, pxPerBeat: 10, bar: 3, x0: 0)
        XCTAssertEqual(threeFour.map(\.label), ["1", "3", "5", "7", "9", "11", "13"])
        XCTAssertEqual(threeFour.map(\.x), [0, 60, 120, 180, 240, 300, 360])
        // 7/8: a bar is 3.5 beats and the lines are counted from their number, not added up.
        let sevenEight = ArrangementRender.rulerMarks(area: area, plot: area, options, end: 12, pxPerBeat: 100, bar: 3.5, x0: 0)
        XCTAssertEqual(sevenEight.map(\.label), ["1", "2", "3"], "the fourth bar line is off the right edge")
        XCTAssertEqual(sevenEight.map(\.x), [0, 350, 700])
    }

    func testManyTracksKeepTheirNameHeightAndScrollInsteadOfSqueezing() {
        let many = space(tracks: 100)
        var v = ArrangementViewport()
        v.ensure(in: many)
        XCTAssertEqual(v.laneH, ArrangementRender.minViewLane(options), "never lower than a name")
        v.scroll(dx: 0, dy: 1_000_000, in: many)
        let contentH = ArrangementRender.lanesHeight(trackCount: 100, laneH: v.laneH, options: options)
        XCTAssertEqual(v.scrollY, Double(contentH) - Double(many.plot.height), "scrolls to the last track and no further")

        let few = space(tracks: 3)
        var w = ArrangementViewport()
        w.ensure(in: few)
        w.scroll(dx: 0, dy: 500, in: few)
        XCTAssertEqual(w.laneH, Int(options.maxLane), "a few tracks fill the height, up to the limit")
        XCTAssertEqual(w.scrollY, 0, "nothing to scroll")
    }

    func testCommandWheelZoomsAroundTheCursorAndStopsAtTheWholeSong() {
        let s = space(tracks: 10)
        var v = ArrangementViewport()
        v.ensure(in: s)
        let fit = v.pxPerBeat
        let cursor = CGPoint(x: s.plot.minX + 400, y: s.plot.midY)
        let beatBefore = (400 + v.scrollX) / v.pxPerBeat
        v.apply(wheel(5, command: true), at: cursor, in: s)
        XCTAssertEqual(v.pxPerBeat, fit * pow(1.25, 5), accuracy: 1e-9)
        XCTAssertEqual((400 + v.scrollX) / v.pxPerBeat, beatBefore, accuracy: 1e-6, "the beat under the cursor stays under it")
        XCTAssertFalse(v.fitted)
        v.apply(wheel(-50, command: true), at: cursor, in: s)
        XCTAssertEqual(v.pxPerBeat, fit, accuracy: 1e-9, "out to the whole song and no further")
        XCTAssertTrue(v.fitted)
    }

    func testOptionWheelResizesTracksAroundTheCursor() {
        let s = space(tracks: 40)
        var v = ArrangementViewport()
        v.ensure(in: s)
        v.scroll(dx: 0, dy: 300, in: s)
        let y = s.plot.minY + 100
        func trackUnderCursor() -> Double {
            (Double(y - s.plot.minY) + v.scrollY) / Double(v.laneH + ArrangementRender.gap(laneH: v.laneH, options: options))
        }
        let before = trackUnderCursor(), laneBefore = v.laneH
        v.apply(wheel(3, option: true), at: CGPoint(x: s.plot.midX, y: y), in: s)
        XCTAssertEqual(v.laneH, laneBefore + 18, "6 px a notch")
        XCTAssertEqual(trackUnderCursor(), before, accuracy: 0.05)
    }

    func testWheelScrollsTracksAndShiftWheelScrollsTime() {
        let s = space(tracks: 100)
        var v = ArrangementViewport()
        v.ensure(in: s)
        let at = CGPoint(x: s.plot.midX, y: s.plot.midY)
        v.apply(wheel(5, command: true), at: at, in: s)           // zoomed in: there is time to scroll
        let start = v.scrollX
        v.apply(wheel(-1), at: at, in: s)                         // one notch down
        XCTAssertEqual(v.scrollY, 60, "the plain wheel scrolls the tracks")
        XCTAssertEqual(v.scrollX, start)
        v.apply(wheel(-1, shift: true), at: at, in: s)
        XCTAssertEqual(v.scrollX, start + 90, "Shift+wheel scrolls the time")
        XCTAssertEqual(v.scrollY, 60)
        v.apply(ArrangementScroll(dx: -30, dy: 0, precise: true), at: at, in: s)
        XCTAssertEqual(v.scrollX, start + 120, "a trackpad swipe sideways moves the time, point for point")
    }

    func testViewDrawsClipsAtTheScrollAndLeavesTheNamesToTheTextLayer() throws {
        var a = Arrangement()
        a.end = 64; a.clipCount = 1
        var t = TrackLane(); t.name = "Drums"; t.color = 14
        var clip = ClipBlock(); clip.start = 0; clip.end = 64; clip.name = "A long clip caption"; clip.color = 14
        t.clips = [clip]
        a.tracks = [t]
        let area = CGRect(x: 0, y: 0, width: 600, height: 200)
        var v = ArrangementViewport()
        v.ensure(in: ArrangementSpace(area: area, arrangement: a, options: options))
        let image = try XCTUnwrap(ArrangementRender.makeViewImage(a, size: area.size, options: options, view: v))
        var px = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        func alpha(_ x: Int, _ y: Int) -> Int { Int(px[(y * image.width + x) * 4 + 3]) }

        let plot = ArrangementRender.plot(area: area, options: options)
        let laneTop = ArrangementRender.viewTop(plot: plot, trackCount: 1, options: options, view: v)
        let rows = laneTop..<(laneTop + v.laneH)
        // A bar line shows through the clip by a point of alpha; a caption would be far darker.
        XCTAssertTrue((Int(plot.minX)..<600).allSatisfy { x in rows.allSatisfy { abs(alpha(x, $0) - 0xEE) <= 3 } },
                      "the clip is one flat colour: no caption on it")
        XCTAssertTrue((0..<Int(plot.minX)).allSatisfy { x in rows.allSatisfy { alpha(x, $0) == 0 } },
                      "the name column is the text layer's, and the clip does not run under it")

        // The text layer, drawn straight onto its own context, carries the name in that column.
        var text = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let textCtx = try XCTUnwrap(CGContext(data: &text, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        textCtx.translateBy(x: 0, y: area.height)
        textCtx.scaleBy(x: 1, y: -1)
        ArrangementRender.drawViewText(textCtx, area: area, arrangement: a, options: options, view: v)
        let nameInk = rows.reduce(0) { sum, y in sum + (0..<Int(plot.minX)).filter { text[(y * image.width + $0) * 4 + 3] > 0 }.count }
        XCTAssertGreaterThan(nameInk, 5)
    }
}
