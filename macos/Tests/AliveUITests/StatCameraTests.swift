import XCTest
import AliveCore
@testable import AliveUI

final class StatCameraTests: XCTestCase {
    private let size = CGSize(width: 600, height: 400)

    func testFrontLooksAlongZ() {
        let cam = CloudCamera()
        XCTAssertEqual(cam.preset, .front)
        let p = cam.projector(size: size)
        let scale = 400 * 0.33
        let a = p.project(1, 0, 0), b = p.project(0, 1, 0), c = p.project(0, 0, 1)
        XCTAssertEqual(a.sx, 300 + scale, accuracy: 1e-9); XCTAssertEqual(a.sy, 200, accuracy: 1e-9)
        XCTAssertEqual(b.sx, 300, accuracy: 1e-9); XCTAssertEqual(b.sy, 200 - scale, accuracy: 1e-9, "y is up")
        XCTAssertEqual(c.sx, 300, accuracy: 1e-9); XCTAssertEqual(c.sy, 200, accuracy: 1e-9, "z points at the eye")
    }

    func testSideLooksAlongX() {
        var cam = CloudCamera()
        cam.setPreset(.side)
        let p = cam.projector(size: size)
        let scale = 400 * 0.33
        let x = p.project(1, 0, 0), z = p.project(0, 0, 1)
        XCTAssertEqual(x.sx, 300, accuracy: 1e-9)
        XCTAssertEqual(z.sx, 300 + scale, accuracy: 1e-9)
    }

    func testTopLooksAlongY() {
        var cam = CloudCamera()
        cam.setPreset(.top)
        let p = cam.projector(size: size)
        let scale = 400 * 0.33
        let y = p.project(0, 1, 0), z = p.project(0, 0, 1)
        XCTAssertEqual(y.sx, 300, accuracy: 1e-9); XCTAssertEqual(y.sy, 200, accuracy: 1e-9)
        XCTAssertEqual(z.sy, 200 - scale, accuracy: 1e-9)
    }

    func testOrthographicIgnoresDepthPerspectiveDoesNot() {
        var cam = CloudCamera()
        let ortho = cam.projector(size: size)
        XCTAssertEqual(ortho.project(0.5, 0.5, -1).k, 1)
        XCTAssertEqual(ortho.project(0.5, 0.5, -1).sx, ortho.project(0.5, 0.5, 1).sx, accuracy: 1e-9)

        cam.setPreset(.angle)
        XCTAssertFalse(cam.isOrtho)
        let persp = cam.projector(size: size)
        let near = persp.project(0, 0, -1), far = persp.project(0, 0, 1)
        XCTAssertNotEqual(near.k, far.k)
        XCTAssertEqual(persp.project(0, 0, 0).k, 1, accuracy: 1e-12, "the middle of the cube is at unit distance factor")
    }

    func testPresetResetsZoomAndPan() {
        var cam = CloudCamera()
        cam.zoomBy(steps: 5); cam.pan(dx: 40, dy: -9); cam.rotate(dx: 30, dy: 10)
        cam.setPreset(.front)
        XCTAssertEqual(cam.zoom, 1); XCTAssertEqual(cam.panX, 0); XCTAssertEqual(cam.panY, 0)
        XCTAssertEqual(cam.yaw, 0); XCTAssertEqual(cam.pitch, 0)
        cam.setPreset(.angle)
        XCTAssertEqual(cam.yaw, 0.72); XCTAssertEqual(cam.pitch, 0.34)
    }

    func testDragRotatesInvertedAndPitchIsClamped() {
        var cam = CloudCamera()
        cam.rotate(dx: 100, dy: 0)
        XCTAssertEqual(cam.yaw, -0.75, accuracy: 1e-9, "dragging right turns the scene left")
        cam.rotate(dx: 0, dy: -10_000)
        XCTAssertEqual(cam.pitch, .pi / 2, accuracy: 1e-12)
        cam.rotate(dx: 0, dy: 10_000)
        XCTAssertEqual(cam.pitch, -.pi / 2, accuracy: 1e-12)
    }

    func testZoomIsClamped() {
        var cam = CloudCamera()
        cam.zoomBy(steps: 1)
        XCTAssertEqual(cam.zoom, 1.12, accuracy: 1e-12)
        cam.zoomBy(steps: 500); XCTAssertEqual(cam.zoom, 6)
        cam.zoomBy(steps: -500); XCTAssertEqual(cam.zoom, 0.35)
    }

    func testZoomAndPanMoveTheProjection() {
        var cam = CloudCamera()
        let base = cam.projector(size: size).project(1, 0, 0)
        cam.zoomBy(steps: 3)
        XCTAssertGreaterThan(cam.projector(size: size).project(1, 0, 0).sx, base.sx)
        cam.setPreset(.front); cam.pan(dx: 25, dy: 5)
        let moved = cam.projector(size: size).project(0, 0, 0)
        XCTAssertEqual(moved.sx, 325, accuracy: 1e-9); XCTAssertEqual(moved.sy, 205, accuracy: 1e-9)
    }
}

final class CloudSceneTests: XCTestCase {
    private let size = CGSize(width: 800, height: 600)
    private func scene(_ sets: [SetEntry]) -> CloudScene {
        let s = CloudScene(metrics: Metrics())
        s.setData(sets)
        return s
    }

    func testCoordinatesFillTheCubeAndStayInsideIt() {
        let sets = (0..<50).map { statSet("s\($0)", tracks: 2 + $0) }
        let s = scene(sets)   // x = tracks by default
        let xs = s.nodes.map(\.x)
        XCTAssertLessThan(xs.min() ?? 0, -0.9); XCTAssertGreaterThan(xs.max() ?? 0, 0.9)
        XCTAssertTrue(xs.allSatisfy { abs($0) <= 1.02 })
        XCTAssertEqual(s.nodes.map(\.x), s.nodes.map(\.tx), "a first build does not animate")
    }

    func testNoDataSitsNearTheCentre() {
        let s = scene([statSet("a", tracks: 0), statSet("b", tracks: 5), statSet("c", tracks: 9)])
        XCTAssertLessThan(abs(s.nodes[0].tx), 0.07)
    }

    func testChannelOffIsNeutral() {
        let s = scene((0..<5).map { statSet("s\($0)", tracks: $0 + 1) })
        s.setChannel(3, metric: Metrics().byId("tracks"), isOn: false)
        s.setChannel(4, metric: Metrics().byId("tracks"), isOn: false)
        s.setChannel(5, metric: Metrics().byId("tracks"), isOn: false)
        s.setChannel(0, metric: Metrics().byId("tracks"), isOn: false)
        s.rebuild(animate: false)
        XCTAssertTrue(s.nodes.allSatisfy { $0.size == CloudScene.sizeWhenOff })
        XCTAssertTrue(s.nodes.allSatisfy { $0.alpha == CloudScene.alphaWhenOff })
        XCTAssertEqual(Set(s.nodes.map(\.rgb)).count, 1, "every dot one neutral colour")
        XCTAssertTrue(s.nodes.allSatisfy { abs($0.tx) < 0.07 }, "an off axis collapses to the centre scatter")
    }

    func testMissingDataInSizeAndFade() {
        let s = scene([statSet("a", tracks: 0), statSet("b", tracks: 5), statSet("c", tracks: 9)])
        s.setChannel(3, metric: Metrics().byId("tracks"), isOn: true)
        s.setChannel(4, metric: Metrics().byId("tracks"), isOn: true)
        s.rebuild(animate: false)
        XCTAssertEqual(s.nodes[0].size, CloudScene.sizeWhenMissing)
        XCTAssertEqual(s.nodes[0].alpha, CloudScene.alphaWhenMissing)
        XCTAssertEqual(s.nodes[2].size, 1, accuracy: 1e-9)
        XCTAssertEqual(s.nodes[2].alpha, 1, accuracy: 1e-9)
        s.setFade(min: 0.2, max: 0.6)
        XCTAssertEqual(s.nodes[1].alpha, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.nodes[2].alpha, 0.6, accuracy: 1e-9)
    }

    func testColourModes() {
        let m = Metrics()
        let a = statSet("a", key: (0, 0, "C Major")), b = statSet("b", key: (7, 1, "G Minor"))
        let s = scene([a, b])
        s.setChannel(5, metric: m.byId("key"), isOn: true); s.rebuild(animate: false)
        XCTAssertEqual(s.nodes[0].rgb, Palette.key(root: 0, scaleIndex: 0).packed)
        XCTAssertEqual(s.nodes[1].rgb, Palette.key(root: 7, scaleIndex: 1).packed)
        s.setChannel(5, metric: m.byId("scale"), isOn: true); s.rebuild(animate: false)
        XCTAssertEqual(s.nodes[1].rgb, Palette.classColor(1).packed)
        s.setChannel(5, metric: m.byId("bpm"), isOn: true); s.rebuild(animate: false)
        let before = s.nodes.map(\.rgb)
        s.setGradient(Palette.gradients[1])
        XCTAssertNotEqual(before, s.nodes.map(\.rgb), "recolouring follows the gradient")
        XCTAssertEqual(s.nodes.map(\.x), s.nodes.map(\.tx), "and does not move the dots")
    }

    func testRebuildAnimatesTowardsTheTargets() {
        let s = scene((0..<10).map { statSet("s\($0)", tracks: 2 + $0) })
        let old = s.nodes.map(\.x)
        s.setChannel(0, metric: Metrics().byId("plugins"), isOn: true)
        s.rebuild(animate: true)
        XCTAssertEqual(s.nodes.map(\.x), old, "starts from the previous places")
        XCTAssertTrue(s.isAnimating)
        for _ in 0..<600 { s.step(dt: 1.0 / 60) }
        XCTAssertFalse(s.isAnimating)
        XCTAssertEqual(s.nodes.map(\.x), s.nodes.map(\.tx))
    }

    func testSettleIsIndependentOfTheFrameRate() {
        func progress(_ fps: Double) -> Double {
            let s = scene((0..<10).map { statSet("s\($0)", tracks: 2 + $0) })
            s.setChannel(0, metric: Metrics().byId("plugins"), isOn: true)
            s.rebuild(animate: true)
            let start = s.nodes[9].x
            for _ in 0..<Int(fps / 5) { s.step(dt: 1 / fps) }     // 0.2 s
            return abs(s.nodes[9].x - start)
        }
        XCTAssertEqual(progress(60), progress(120), accuracy: 0.02)
    }

    func testSpinAdvancesTheYawUnlessDragging() {
        let s = scene([statSet("a")])
        s.isSpinning = true
        s.step(dt: 1)
        XCTAssertEqual(s.camera.yaw, CloudScene.spinSpeed, accuracy: 1e-9)
        s.isDragging = true
        s.step(dt: 1)
        XCTAssertEqual(s.camera.yaw, CloudScene.spinSpeed, accuracy: 1e-9)
        XCTAssertFalse(s.isAnimating, "a held cloud does not ask for frames")
    }

    func testInertiaDecaysToRest() {
        let s = scene([statSet("a")])
        s.fling(yawPerSecond: 2, pitchPerSecond: 0)
        XCTAssertTrue(s.isAnimating)
        s.step(dt: 1.0 / 60)
        XCTAssertGreaterThan(s.camera.yaw, 0)
        for _ in 0..<2000 { s.step(dt: 1.0 / 60) }
        XCTAssertFalse(s.isAnimating)
    }

    func testAdvanceClampsALongPause() {
        let s = scene([statSet("a")])
        s.isSpinning = true
        let t0 = Date()
        s.advance(to: t0)
        s.advance(to: t0.addingTimeInterval(3600))
        XCTAssertLessThan(s.camera.yaw, 0.01, "an hour between frames is one short step")
    }

    func testPickPrefersTheNearerDotAndMissesEmptySpace() {
        let s = scene([statSet("far", tracks: 10), statSet("near", tracks: 10)])
        s.camera.setPreset(.angle)
        s.project(size: size)
        // Put both dots on the same pixel; the nearer (larger k) wins.
        var nodes = s.nodes
        nodes[0].sx = 100; nodes[0].sy = 100; nodes[0].sr = 8; nodes[0].depth = 0.8
        nodes[1].sx = 100; nodes[1].sy = 100; nodes[1].sr = 8; nodes[1].depth = 1.2
        XCTAssertEqual(CloudScene.pick(in: nodes, x: 100, y: 100), 1)
        XCTAssertEqual(CloudScene.pick(in: nodes, x: 400, y: 400), -1)
    }

    func testPickUsesTheProjectedPositionsAndAMinimumReach() {
        let s = scene([statSet("a", tracks: 2), statSet("b", tracks: 30)])
        s.project(size: size)
        let n = s.nodes[1]
        XCTAssertEqual(s.pick(x: n.sx, y: n.sy), 1)
        XCTAssertEqual(s.pick(x: n.sx + 8, y: n.sy), 1, "a tiny dot is still easy to hit (9 pt reach)")
        XCTAssertEqual(s.pick(x: n.sx + 200, y: n.sy + 200), -1)
    }

    func testSelectionFollowsThePathAcrossNewData() {
        let a = statSet("a"), b = statSet("b")
        let s = scene([a, b])
        XCTAssertTrue(s.select(path: b.path))
        XCTAssertEqual(s.selectedSet?.path, b.path)
        s.setData([statSet("c"), b])
        XCTAssertEqual(s.selectedSet?.path, b.path, "the same set keeps the selection when the list changes")
        s.setData([statSet("c")])
        XCTAssertNil(s.selectedSet)
        XCTAssertFalse(s.select(path: "/nope.als"))
        XCTAssertNil(s.selectedSet)
    }

    func testTwoThousandDotsProjectQuickly() {
        let s = scene((0..<2000).map { statSet("s\($0)", tracks: 2 + $0 % 90, tempo: 80 + Double($0 % 100)) })
        measure { s.project(size: size) }
    }
}
