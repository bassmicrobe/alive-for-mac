import AppKit
import CoreGraphics
import XCTest
@testable import AliveCore
@testable import AliveUI

/// Synthetic arrangements: two audio clips, one midi clip with notes, an empty group.
enum SyntheticArrangement {
    static func make() -> Arrangement {
        var a = Arrangement()
        a.path = "/tmp/x.als"
        a.tempo = 128
        var drums = TrackLane(); drums.name = "Drums"; drums.color = 14
        var kick = ClipBlock(); kick.start = 0; kick.end = 16; kick.name = "kick"; kick.color = 14
        var kick2 = ClipBlock(); kick2.start = 24; kick2.end = 32; kick2.name = "kick 2"; kick2.color = 14; kick2.disabled = true
        drums.clips = [kick, kick2]
        var keys = TrackLane(); keys.name = "Keys"; keys.color = 26; keys.isMidi = true
        var pad = ClipBlock(); pad.start = 8; pad.end = 24; pad.name = "pad"; pad.color = 26; pad.isMidi = true
        pad.loopStart = 0; pad.loopEnd = 4; pad.loopOn = true
        pad.notes = [NoteEvent(time: 0, duration: 1, pitch: 60, velocity: 100), NoteEvent(time: 2, duration: 1, pitch: 67, velocity: 100)]
        pad.minPitch = 60; pad.maxPitch = 67
        keys.clips = [pad]
        var group = TrackLane(); group.name = "Group"; group.color = 5; group.isGroup = true
        a.tracks = [drums, keys, group]
        a.end = 32
        a.clipCount = 3
        a.noteCount = 2
        return a
    }
}

final class ArrangementRenderTests: XCTestCase {
    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// RGBA of the pixel at (x, y) counted from the top.
    private func pixel(_ data: [UInt8], _ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        // A bitmap context keeps its top row first in memory.
        let i = (y * image.width + x) * 4
        return (Int(data[i + 2]), Int(data[i + 1]), Int(data[i]), Int(data[i + 3]))
    }

    func testImageHasRequestedSizeAndContent() throws {
        let image = try XCTUnwrap(ArrangementRender.makeImage(SyntheticArrangement.make(), width: 480, height: 270, options: .thumbnail))
        XCTAssertEqual(image.width, 480)
        XCTAssertEqual(image.height, 270)
        let data = pixels(image)
        let opaque = stride(from: 3, to: data.count, by: 4).filter { data[$0] > 0 }.count
        XCTAssertGreaterThan(opaque, 500, "clips must leave pixels")
        XCTAssertLessThan(opaque, 480 * 270, "the background stays transparent")
    }

    func testClipUsesItsLiveColour() throws {
        let image = try XCTUnwrap(ArrangementRender.makeImage(SyntheticArrangement.make(), width: 480, height: 270, options: .thumbnail))
        let data = pixels(image)
        let lay = ArrangementRender.layout(area: CGRect(x: 0, y: 0, width: 480, height: 270), trackCount: 3, options: .thumbnail)
        // Middle of the first (audio) clip: colour 14 of the palette at 0xEE alpha, premultiplied.
        let want = LiveColors.get(14)
        let p = pixel(data, image, 480 * 8 / 32, lay.top + lay.laneH / 2)
        XCTAssertEqual(p.a, 0xEE, accuracy: 2)
        XCTAssertEqual(p.r, Int(want.r) * 0xEE / 255, accuracy: 3)
        XCTAssertEqual(p.g, Int(want.g) * 0xEE / 255, accuracy: 3)
        XCTAssertEqual(p.b, Int(want.b) * 0xEE / 255, accuracy: 3)
    }

    func testMidiClipBodyIsMutedAndNotesAreDrawnOverIt() throws {
        let opts = RenderOptions(scale: 3)
        let image = try XCTUnwrap(ArrangementRender.makeImage(SyntheticArrangement.make(), width: 960, height: 540, options: opts))
        let data = pixels(image)
        let lay = ArrangementRender.layout(area: CGRect(x: 0, y: 0, width: 960, height: 540), trackCount: 3, options: opts)
        let y0 = lay.top + (lay.laneH + lay.gap)      // second lane
        var alphas = Set<Int>()
        for y in y0..<(y0 + lay.laneH) {
            for x in stride(from: 960 * 8 / 32, to: 960 * 24 / 32, by: 1) { alphas.insert(pixel(data, image, x, y).a) }
        }
        XCTAssertTrue(alphas.contains { abs($0 - 0x59) <= 2 }, "muted body: \(alphas.sorted())")
        XCTAssertTrue(alphas.contains(255), "notes are drawn opaque over the body")
    }

    func testNoTracksLeavesTheImageTransparent() throws {
        let image = try XCTUnwrap(ArrangementRender.makeImage(Arrangement(), width: 64, height: 36, options: .thumbnail))
        XCTAssertFalse(pixels(image).contains { $0 != 0 })
    }

    func testZeroSizeGivesNoImage() {
        XCTAssertNil(ArrangementRender.makeImage(SyntheticArrangement.make(), width: 0, height: 10, options: .thumbnail))
    }

    func testLaneHeightIsClampedAndBlockCentred() {
        let o = RenderOptions.thumbnail
        let few = ArrangementRender.layout(area: CGRect(x: 0, y: 0, width: 400, height: 300), trackCount: 2, options: o)
        XCTAssertEqual(few.laneH, ArrangementRender.px(o, o.maxLane))
        XCTAssertGreaterThan(few.top, 0, "few tracks are centred, not pushed to the top")
        let many = ArrangementRender.layout(area: CGRect(x: 0, y: 0, width: 400, height: 100), trackCount: 300, options: o)
        XCTAssertEqual(many.laneH, ArrangementRender.px(o, o.minLane))
        XCTAssertEqual(many.gap, 1)
    }

    func testNamesAndRulerOnlyWhenAskedAndRoomy() {
        let preview = RenderOptions.preview(scale: 1)
        let wide = ArrangementRender.layout(area: CGRect(x: 0, y: 0, width: 1000, height: 400), trackCount: 8, options: preview)
        XCTAssertEqual(wide.nameW, 170)
        XCTAssertEqual(wide.rulerH, 24)
        let narrow = ArrangementRender.layout(area: CGRect(x: 0, y: 0, width: 300, height: 400), trackCount: 8, options: preview)
        XCTAssertEqual(narrow.nameW, 0)
        let thumb = ArrangementRender.layout(area: CGRect(x: 0, y: 0, width: 1000, height: 400), trackCount: 8, options: .thumbnail)
        XCTAssertEqual(thumb.nameW, 0)
        XCTAssertEqual(thumb.rulerH, 0)
    }

    func testPreviewWithTextDrawsTrackNames() throws {
        let opts = RenderOptions.preview(scale: 1)
        let image = try XCTUnwrap(ArrangementRender.makeImage(SyntheticArrangement.make(), width: 1200, height: 500, options: opts))
        let data = pixels(image)
        let lay = ArrangementRender.layout(area: CGRect(x: 0, y: 0, width: 1200, height: 500), trackCount: 3, options: opts)
        var textPixels = 0
        for y in lay.top..<(lay.top + lay.laneH) {
            for x in 0..<lay.nameW where pixel(data, image, x, y).a > 0 { textPixels += 1 }
        }
        XCTAssertGreaterThan(textPixels, 5, "track name is drawn in the left column")
    }

    func testFullHeightGivesEveryTrackItsLane() {
        let o = RenderOptions.preview(scale: 1, minLane: 14)
        XCTAssertEqual(ArrangementRender.fullHeight(trackCount: 10, options: o), 14 * 10 + 2 * 9 + 24)
    }

    /// Gated: renders a real set into `ALIVE_TEST_RENDER_OUT` (a folder) so the picture can be looked at.
    /// `ALIVE_TEST_RENDER_SET` is the .als to read (read-only).
    func testRealSetRendersToPng() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["ALIVE_TEST_RENDER_OUT"], let set = env["ALIVE_TEST_RENDER_SET"] else {
            throw XCTSkip("ALIVE_TEST_RENDER_OUT / ALIVE_TEST_RENDER_SET not set")
        }
        let a = Arrangement.read(path: set)
        XCTAssertTrue(a.hasContent)
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        for (name, w, h, o) in [("thumb", 480, 270, RenderOptions.thumbnail), ("preview", 2200, 1300, RenderOptions.preview(scale: 2))] {
            let image = try XCTUnwrap(ArrangementRender.makeImage(a, width: w, height: h, options: o))
            let rep = NSBitmapImageRep(cgImage: image)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: out + "/\(name).png"))
        }
    }
}
