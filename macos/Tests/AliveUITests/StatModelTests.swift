import XCTest
import AliveCore
@testable import AliveUI

final class NebulaConfigTests: XCTestCase {
    private func scratch() -> String {
        let dir = NSTemporaryDirectory() + "alive-nebula-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testDefaultsAreUpstreams() {
        let c = NebulaConfig()
        XCTAssertEqual(c.ids, ["tracks", "plugins", "bpm", "setsize", "created", "live"])
        XCTAssertEqual(c.isOn, Array(repeating: true, count: 6))
        XCTAssertFalse(c.spin)
        XCTAssertEqual(c.minFade, 0.08); XCTAssertEqual(c.maxFade, 1)
        XCTAssertEqual(c.minSize, 1); XCTAssertEqual(c.maxSize, 16)
        XCTAssertEqual(c.gradientId, "nebula")
    }

    func testMissingFileGivesDefaults() {
        XCTAssertEqual(NebulaConfig.load(dir: scratch()), NebulaConfig())
    }

    func testRoundTrip() throws {
        var c = NebulaConfig()
        c.ids = ["bpm", "key", "scale", "projsize", "name", "place"]
        c.isOn = [true, false, true, true, false, true]
        c.spin = true; c.minFade = 0.25; c.maxFade = 0.9; c.minSize = 2.5; c.maxSize = 30
        c.gradientId = "ocean"
        let dir = scratch()
        try c.save(dir: dir)
        XCTAssertEqual(NebulaConfig.load(dir: dir), c)
    }

    func testFileFormatIsUpstreams() throws {
        let text = NebulaConfig().serialized()
        XCTAssertTrue(text.hasPrefix("# Nebula — what each channel shows, and whether it's on\n"))
        for line in ["x=tracks", "x_on=1", "y=plugins", "z=bpm", "size=setsize", "fade=created", "colour=live",
                     "colour_on=1", "spin=0", "blur=0.04", "minfade=0.08", "maxfade=1", "minsize=1",
                     "maxsize=16", "gradient=nebula"] {
            XCTAssertTrue(text.contains(line + "\n"), line)
        }
    }

    func testReadsAnUpstreamFile() {
        let c = NebulaConfig(lines: ["# Nebula", "x=bpm", "x_on=0", "colour=key", "spin=1", "blur=0.05",
                                     "minfade=0.1", "maxsize=20.5", "gradient=ocean"])
        XCTAssertEqual(c.ids[0], "bpm"); XCTAssertFalse(c.isOn[0]); XCTAssertTrue(c.isOn[1])
        XCTAssertEqual(c.ids[5], "key"); XCTAssertTrue(c.spin)
        XCTAssertEqual(c.blur, 0.05); XCTAssertEqual(c.minFade, 0.1); XCTAssertEqual(c.maxSize, 20.5)
        XCTAssertEqual(c.gradientId, "ocean")
    }

    func testUnknownIdsAndValuesAreRepaired() {
        let c = NebulaConfig(lines: ["x=nonsense", "gradient=neon", "minsize=99", "maxsize=1", "minfade=-3", "maxfade=abc",
                                     "minsize=nan", "spin=yes"])
        XCTAssertEqual(c.ids[0], "tracks")
        XCTAssertEqual(c.gradientId, "nebula")
        XCTAssertEqual(c.maxSize, 4, "clamped to the slider's range")
        XCTAssertEqual(c.minSize, 1, "a NaN falls back to the default")
        XCTAssertEqual(c.minFade, 0)
        XCTAssertEqual(c.maxFade, 1)
        XCTAssertFalse(c.spin, "only 1 switches a flag on")
    }

    func testUnknownLinesSurviveARoundTrip() {
        let c = NebulaConfig(lines: ["x=bpm", "future_key=42", "# comment", "no equals sign"])
        XCTAssertEqual(c.unknownLines, ["future_key=42"])
        XCTAssertTrue(c.serialized().contains("future_key=42\n"))
        XCTAssertEqual(NebulaConfig(lines: c.serialized().components(separatedBy: "\n")).unknownLines, ["future_key=42"])
    }

    func testNumbersAreInvariant() {
        XCTAssertEqual(NebulaConfig.number(0.04, decimals: 3), "0.04")
        XCTAssertEqual(NebulaConfig.number(1, decimals: 3), "1")
        XCTAssertEqual(NebulaConfig.number(2.50, decimals: 2), "2.5")
        XCTAssertEqual(NebulaConfig.number(0.0004, decimals: 3), "0")
        XCTAssertEqual(NebulaConfig.number(-0.0001, decimals: 3), "0")
    }

    func testCRLFFilesFromWindowsRead() throws {
        let dir = scratch()
        try "x=bpm\r\ny=key\r\nspin=1\r\n".write(toFile: NebulaConfig.path(dir: dir), atomically: true, encoding: .utf8)
        let c = NebulaConfig.load(dir: dir)
        XCTAssertEqual(c.ids[0], "bpm"); XCTAssertEqual(c.ids[1], "key"); XCTAssertTrue(c.spin)
    }
}

final class StatLegendTests: XCTestCase {
    private func scene(_ sets: [SetEntry], colour: String) -> CloudScene {
        let m = Metrics()
        let s = CloudScene(metrics: m)
        s.setData(sets)
        s.setChannel(5, metric: m.byId(colour), isOn: true)
        s.rebuild(animate: false)
        return s
    }

    func testOff() {
        let s = scene([statSet("a")], colour: "bpm")
        s.setChannel(5, metric: Metrics().byId("bpm"), isOn: false)
        XCTAssertEqual(StatLegend.make(scene: s), .off)
    }

    func testRampCarriesTheEdgeLabels() {
        let s = scene([statSet("a", tempo: 90), statSet("b", tempo: 140)], colour: "bpm")
        guard case .ramp(let g, let lo, let hi) = StatLegend.make(scene: s) else { return XCTFail() }
        XCTAssertEqual(g.id, "nebula"); XCTAssertEqual(lo, "90"); XCTAssertEqual(hi, "140")
    }

    func testClassesAreMostPopulatedFirstAndCapped() {
        var sets: [SetEntry] = []
        for i in 0..<12 { for j in 0...(i % 4) { sets.append(statSet("s\(i)-\(j)", key: (i, 0, "K\(i)"))) } }
        let s = scene(sets, colour: "key")
        guard case .classes(let chips) = StatLegend.make(scene: s) else { return XCTFail() }
        XCTAssertEqual(chips.count, StatLegend.maxChips)
        XCTAssertEqual(chips.map(\.count), chips.map(\.count).sorted(by: >))
        XCTAssertEqual(chips.first?.count, 4)
        XCTAssertEqual(chips[0].rgb, Palette.key(root: 3, scaleIndex: 0), "first of the most populated")
    }

    func testSetsWithoutTheValueAreLeftOut() {
        let s = scene([statSet("a", key: (-1, -1, "")), statSet("b", key: (2, 0, "D Major"))], colour: "key")
        guard case .classes(let chips) = StatLegend.make(scene: s) else { return XCTFail() }
        XCTAssertEqual(chips.map(\.name), ["D Major"])
    }
}

final class CloudAxisLabelsTests: XCTestCase {
    private let size = CGSize(width: 800, height: 600)
    private func measure(_ text: String, _ title: Bool) -> CGSize {
        CGSize(width: Double(text.count) * (title ? 7 : 6), height: title ? 15 : 14)
    }

    private func scene() -> CloudScene {
        let s = CloudScene(metrics: Metrics())
        s.setData((0..<40).map { statSet("s\($0)", tracks: 2 + $0, tempo: 80 + Double($0)) })
        return s
    }

    func testFrontViewPutsTheLabelsOutsideTheCube() {
        let s = scene()
        let labels = CloudAxisLabels.layout(scene: s, size: size, titles: ["X · Tracks", "Y · Plugins", "Z · BPM"], measure: measure)
        let titles = labels.filter(\.isTitle)
        // Z runs straight at the eye in the front view: an edge with no length has no label.
        XCTAssertEqual(titles.map(\.text), ["X · Tracks", "Y · Plugins"])
        let x = titles[0], y = titles[1]
        XCTAssertGreaterThan(x.center.y, 300, "the X title sits under the cube")
        XCTAssertLessThan(y.center.x, 400, "the Y title sits to the left")
        XCTAssertEqual(labels.filter { !$0.isTitle && !$0.text.isEmpty }.count, 4, "X and Y each carry two values")
    }

    func testOffAxisHasOnlyADimTitle() {
        let s = scene()
        s.setChannel(1, metric: Metrics().byId("plugins"), isOn: false)
        s.rebuild(animate: false)
        let labels = CloudAxisLabels.layout(scene: s, size: size, titles: ["X", "Y · Off", "Z"], measure: measure)
        let y = labels.first { $0.text == "Y · Off" }
        XCTAssertEqual(y?.isDim, true)
    }

    func testLabelsStayInsideTheCanvas() {
        let s = scene()
        s.camera.zoomBy(steps: 10)
        for l in CloudAxisLabels.layout(scene: s, size: size, titles: ["X · Tracks", "Y · Plugins", "Z · BPM"], measure: measure) {
            XCTAssertGreaterThanOrEqual(l.center.x, 0); XCTAssertLessThanOrEqual(l.center.x, size.width)
            XCTAssertGreaterThanOrEqual(l.center.y, 0); XCTAssertLessThanOrEqual(l.center.y, size.height)
        }
    }

    func testEdgeHysteresisKeepsTheChosenEdge() {
        let s = scene()
        s.camera.setPreset(.angle)
        _ = CloudAxisLabels.layout(scene: s, size: size, titles: ["X", "Y", "Z"], measure: measure)
        let chosen = s.lastEdge
        XCTAssertTrue(chosen.allSatisfy { $0 >= 0 })
        s.camera.yaw += 0.01
        _ = CloudAxisLabels.layout(scene: s, size: size, titles: ["X", "Y", "Z"], measure: measure)
        XCTAssertEqual(s.lastEdge, chosen, "a small turn does not switch the edge")
    }

    func testCandidatesLieOnTheCube() {
        for dim in 0..<3 {
            for i in 0..<(dim == 1 ? 4 : 2) {
                let c = CloudAxisLabels.candidate(dim: dim, i)
                for p in [c.a, c.b] { XCTAssertTrue([p.0, p.1, p.2].allSatisfy { abs($0) == 1 }) }
            }
        }
    }
}

@MainActor
final class StatModelTests: XCTestCase {
    private func model() throws -> (AppModel, StatModel) {
        let app = try makeModel()
        return (app, app.stat)
    }

    func testStartsFromDefaultsWithNoNebulaCfg() throws {
        let (_, m) = try model()
        XCTAssertEqual(m.config, NebulaConfig())
        XCTAssertEqual(m.scene.x.metric.id, "tracks")
        XCTAssertEqual(m.scene.camera.preset, .front)
        XCTAssertFalse(m.showsPalette == false, "Live version is a ramp: the palette is offered")
    }

    func testLoadsAnExistingNebulaCfg() throws {
        let app = try makeModel(files: ["nebula.cfg": "x=bpm\ncolour=key\nspin=1\ngradient=ocean\n"])
        XCTAssertEqual(app.stat.scene.x.metric.id, "bpm")
        XCTAssertTrue(app.stat.scene.isSpinning)
        XCTAssertFalse(app.stat.showsPalette, "key colours by class, the palette decides nothing")
        XCTAssertEqual(app.stat.scene.gradient.id, "ocean")
    }

    func testChannelChangesPersistToNebulaCfg() throws {
        let (app, m) = try model()
        m.setMetric(1, id: "key")
        m.setChannel(2, isOn: false)
        m.setGradient(id: "ocean")
        m.setMinFade(0.3); m.setMaxSize(24)
        m.setSpin(true)
        m.saveNow()
        let back = NebulaConfig.load(dir: app.dataDir)
        XCTAssertEqual(back.ids[1], "key"); XCTAssertFalse(back.isOn[2]); XCTAssertEqual(back.gradientId, "ocean")
        XCTAssertEqual(back.minFade, 0.3); XCTAssertEqual(back.maxSize, 24); XCTAssertTrue(back.spin)
        XCTAssertEqual(m.scene.y.metric.id, "key"); XCTAssertFalse(m.scene.z.isOn)
    }

    func testPresetsSwitchSpinOffAndResetTheCamera() throws {
        let (_, m) = try model()
        m.setSpin(true)
        m.zoom(steps: 4)
        m.setPreset(.top)
        XCTAssertFalse(m.config.spin); XCTAssertFalse(m.scene.isSpinning)
        XCTAssertEqual(m.scene.camera.preset, .top); XCTAssertEqual(m.scene.camera.zoom, 1)
        m.rotate(dx: 50, dy: 0)
        m.resetView()
        XCTAssertEqual(m.scene.camera.preset, .front); XCTAssertEqual(m.scene.camera.yaw, 0)
    }

    func testVisibleSetsDropBackupsAndErrors() {
        var bad = statSet("bad"); bad.error = "corrupt"
        var backup = statSet("bk"); backup.isBackup = true
        XCTAssertEqual(StatModel.visibleSets(from: [statSet("ok"), bad, backup]).map(\.name), ["ok"])
    }

    func testClickSelectsAndShowInListSelectsInTheSetsTab() throws {
        let (app, m) = try model()
        let a = statSet("a", tracks: 3), b = statSet("b", tracks: 40)
        m.scene.setData([a, b])
        m.scene.project(size: CGSize(width: 800, height: 600))
        let n = m.scene.nodes[1]
        m.click(x: n.sx, y: n.sy)
        XCTAssertEqual(m.selectedSet?.path, b.path)

        app.tab = .home; app.searchText = "something"
        XCTAssertTrue(m.showSelectedInList())
        XCTAssertEqual(app.tab, .sets)
        XCTAssertEqual(app.searchText, "")
        XCTAssertEqual(app.selectedSetPath, b.path)

        m.click(x: 5, y: 5)
        XCTAssertNil(m.selectedSet, "a click on empty space clears the selection")
        XCTAssertFalse(m.showSelectedInList())
    }

    func testMainWindowSelectionRingsTheDot() throws {
        let (app, m) = try model()
        let a = statSet("a"), b = statSet("b")
        m.scene.setData([a, b])
        app.selectedSetPath = b.path
        m.followMainSelection()
        XCTAssertEqual(m.selectedSet?.path, b.path)
        app.selectedSetPath = "/not/in/the/cloud.als"
        m.followMainSelection()
        XCTAssertEqual(m.selectedSet?.path, b.path, "an unknown path leaves the ring alone")
    }

    func testHoverTracksThePointer() throws {
        let (_, m) = try model()
        m.scene.setData([statSet("a", tracks: 3), statSet("b", tracks: 40)])
        m.scene.project(size: CGSize(width: 800, height: 600))
        let n = m.scene.nodes[0]
        XCTAssertTrue(m.hover(x: n.sx, y: n.sy))
        XCTAssertEqual(m.hoveredName, "a")
        XCTAssertFalse(m.hover(x: n.sx, y: n.sy), "no change, no redraw")
        XCTAssertTrue(m.hover(x: nil, y: nil))
        XCTAssertEqual(m.hoveredName, "")
    }
}
