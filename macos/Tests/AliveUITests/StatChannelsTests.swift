import XCTest
import AliveCore
@testable import AliveUI

/// A synthetic set: only what the Stat channels look at.
func statSet(_ name: String, path: String? = nil, tracks: Int = 10, tempo: Double = 120, plugins: [String] = [],
             created: Date = Date(timeIntervalSince1970: 1_500_000_000), projectSize: Int64 = 1_000_000,
             key: (root: Int, scale: Int, text: String) = (0, 0, "C Major"), creator: String = "Ableton Live 12.1.5") -> SetEntry {
    var s = SetEntry()
    s.name = name
    s.path = path ?? "/Music/Shelf/\(name) Project/\(name).als"
    s.tracks = tracks
    s.tempo = tempo
    s.plugins = plugins
    s.created = created
    s.modified = created
    s.size = 250_000
    s.projectSize = projectSize
    s.scaleRoot = key.root
    s.scaleIndex = key.scale
    s.key = key.text
    s.creator = creator
    return s
}

final class StatChannelsTests: XCTestCase {
    let metrics = Metrics()

    func testMetricIdsAreUpstreamsInOrder() {
        XCTAssertEqual(metrics.all.map(\.id), Metrics.ids)
        XCTAssertEqual(metrics.all.count, 16)
        XCTAssertEqual(metrics.byId("nonsense").id, "tracks")
        XCTAssertEqual(metrics.index(of: "bpm"), 2)
    }

    func testMissingDataIsNaNNotZero() {
        var s = statSet("a", tracks: 0, tempo: 0, key: (-1, -1, ""), creator: "")
        s.projectSize = 0
        s.size = 0
        s.created = .distantPast
        for id in ["tracks", "bpm", "key", "scale", "projsize", "setsize", "created", "modified", "live"] {
            XCTAssertTrue(metrics.byId(id).value(s).isNaN, id)
        }
        XCTAssertEqual(metrics.byId("plugins").value(s), 0)
        XCTAssertEqual(metrics.byId("files").value(s), 0)
        XCTAssertEqual(metrics.byId("tracks").text(s), "—")
        XCTAssertEqual(metrics.byId("key").text(s), "—")
        XCTAssertEqual(metrics.byId("projsize").text(s), "…")
    }

    func testValuesAndText() {
        var s = statSet("a", tracks: 24, tempo: 127.5, plugins: ["A", "B"])
        s.totalRefs = 7
        s.missingFiles = 2
        s.missingPlugins = 1
        XCTAssertEqual(metrics.byId("tracks").value(s), 24)
        XCTAssertEqual(metrics.byId("bpm").text(s), "127.5")
        XCTAssertEqual(metrics.byId("plugins").value(s), 2)
        XCTAssertEqual(metrics.byId("files").value(s), 7)
        XCTAssertEqual(metrics.byId("missfiles").value(s), 2)
        XCTAssertEqual(metrics.byId("missplugins").value(s), 1)
        XCTAssertEqual(metrics.byId("key").value(s), 0)
        XCTAssertEqual(metrics.byId("scale").text(s), "Major")
        XCTAssertEqual(statSet("b", tempo: 120).tempo, 120)
        XCTAssertEqual(metrics.byId("bpm").text(statSet("b", tempo: 120)), "120")
    }

    func testCategoricalAndLogFlags() {
        XCTAssertTrue(metrics.byId("key").isCategorical)
        XCTAssertEqual(metrics.byId("key").color, .key)
        XCTAssertEqual(metrics.byId("scale").color, .classes)
        XCTAssertEqual(metrics.byId("place").color, .classes)
        XCTAssertTrue(metrics.byId("projsize").isLog)
        XCTAssertTrue(metrics.byId("setsize").isLog)
        XCTAssertTrue(metrics.byId("files").isLog)
        XCTAssertFalse(metrics.byId("bpm").isLog)
        XCTAssertEqual(metrics.byId("bpm").color, .ramp)
    }

    func testVersionConversion() {
        XCTAssertEqual(Metrics.version("12.3.5"), 12.0305, accuracy: 1e-9)
        XCTAssertEqual(Metrics.version("11.0.11"), 11.0011, accuracy: 1e-9)
        XCTAssertTrue(Metrics.version("").isNaN)
        XCTAssertTrue(Metrics.version("x.y").isNaN)
        XCTAssertLessThan(Metrics.version("11.3.20"), Metrics.version("12.0.0"))
        XCTAssertLessThan(Metrics.version("12.0.5"), Metrics.version("12.1.0"))
    }

    func testBytesText() {
        XCTAssertEqual(Metrics.bytes(0), "—")
        XCTAssertEqual(Metrics.bytes(2048), "2 KB")
        XCTAssertEqual(Metrics.bytes(5 * 1_048_576), "5 MB")
        XCTAssertEqual(Metrics.bytes(3 * 1_073_741_824 / 2), "1.5 GB")
    }

    func testAlphabeticalIsMonotonic() {
        let names = ["", "A", "apple", "Apricot", "b", "bass", "Zeta", "1st", "9", "_x"]
        // letters < digits < others, and inside a class alphabetical, case-insensitively.
        XCTAssertLessThan(Metrics.alphabetical("apple"), Metrics.alphabetical("Apricot"))
        XCTAssertLessThan(Metrics.alphabetical("Apricot"), Metrics.alphabetical("b"))
        XCTAssertLessThan(Metrics.alphabetical("bass"), Metrics.alphabetical("Zeta"))
        XCTAssertEqual(Metrics.alphabetical("APPLE"), Metrics.alphabetical("apple"))
        XCTAssertLessThan(Metrics.alphabetical("Zeta"), Metrics.alphabetical("1st"))
        XCTAssertLessThan(Metrics.alphabetical("1st"), Metrics.alphabetical("9"))
        XCTAssertLessThan(Metrics.alphabetical("9"), Metrics.alphabetical("_x"))
        XCTAssertEqual(Metrics.alphabetical(""), 0)
        XCTAssertEqual(names.count, 10)
    }

    func testHashIsStableFNV() {
        // Pinned vectors: the cloud must not jump between runs or after a port change.
        XCTAssertEqual(Metrics.hash(""), 0)
        XCTAssertEqual(Metrics.hash("a"), 0x640C292C)          // FNV-1a 32 of "a" is 0xE40C292C, top bit cleared
        XCTAssertEqual(Metrics.hash("A"), Metrics.hash("a"), "the hash ignores case")
        let v = Metrics.hash01("/Users/x/Song Project/Song.als")
        XCTAssertGreaterThanOrEqual(v, 0)
        XCTAssertLessThan(v, 1)
        XCTAssertEqual(v, Metrics.hash01("/USERS/X/SONG PROJECT/SONG.ALS"))
    }

    func testCollectionsAreNumberedByFirstAppearanceWithoutSharedState() {
        let a = Metrics(), b = Metrics()
        let one = statSet("1", path: "/Music/Alpha/1 Project/1.als")
        let two = statSet("2", path: "/Music/Beta/2 Project/2.als")
        XCTAssertEqual(a.byId("place").value(two), 0)
        XCTAssertEqual(a.byId("place").value(one), 1)
        XCTAssertEqual(a.byId("place").value(two), 0)
        XCTAssertEqual(b.byId("place").value(one), 0, "a second window numbers on its own")
        XCTAssertEqual(a.byId("place").text(one), "Alpha")
    }

    func testDates() {
        XCTAssertTrue(Metrics.days(.distantPast).isNaN)
        XCTAssertTrue(Metrics.days(Date(timeIntervalSince1970: 0)).isNaN)   // 1970 is before 1990
        XCTAssertEqual(Metrics.dateText(.distantPast), "—")
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertGreaterThan(Metrics.days(d), 12_000)
        XCTAssertEqual(Metrics.dateText(d).count, 10)
        XCTAssertLessThan(Metrics.days(d), Metrics.days(d.addingTimeInterval(86_400)))
    }
}

final class ValueRangeTests: XCTestCase {
    let metrics = Metrics()

    private func sets(_ tracks: [Int]) -> [SetEntry] { tracks.enumerated().map { statSet("s\($0.offset)", tracks: $0.element) } }

    func testSmallSetsUseMinAndMax() {
        let r = ValueRange(sets: sets([4, 10, 20]), metric: metrics.byId("tracks"))
        XCTAssertEqual(r.lo, 4); XCTAssertEqual(r.hi, 20)
        XCTAssertEqual(r.norm(4), 0); XCTAssertEqual(r.norm(20), 1); XCTAssertEqual(r.norm(12), 0.5)
    }

    func testPercentileEdgesClampTheMonster() {
        var t = Array(repeating: 10, count: 98)
        t += [20, 1000]
        t = t.enumerated().map { $0.offset % 2 == 0 ? $0.element : $0.element + 1 }
        let r = ValueRange(sets: sets(t), metric: metrics.byId("tracks"))
        XCTAssertLessThan(r.hi, 1000, "the 98th percentile, not the maximum")
        XCTAssertEqual(r.norm(1_000_000), 1, "beyond the edge clamps")
    }

    func testCategoriesUseTheWholeRange() {
        let s = (0..<30).map { i in statSet("s\(i)", key: (i == 29 ? 11 : 0, 0, "x")) }
        let r = ValueRange(sets: s, metric: metrics.byId("key"))
        XCTAssertEqual(r.lo, 0); XCTAssertEqual(r.hi, 11, "the single set in a rare class still lands on the scale")
    }

    func testDegenerateRangeWidens() {
        let r = ValueRange(sets: sets([5, 5, 5]), metric: metrics.byId("tracks"))
        XCTAssertEqual(r.hi - r.lo, 1, accuracy: 1e-9)
        XCTAssertEqual(r.norm(5), 0.5, accuracy: 1e-9)
    }

    func testLogScale() {
        var s = [statSet("a"), statSet("b"), statSet("c")]
        s[0].projectSize = 1_000; s[1].projectSize = 1_000_000; s[2].projectSize = 1_000_000_000
        let m = metrics.byId("projsize")
        let r = ValueRange(sets: s, metric: m)
        XCTAssertTrue(r.isLog)
        XCTAssertEqual(r.norm(1_000_000), 0.5, accuracy: 0.01, "geometric middle sits in the middle")
        XCTAssertEqual(r.at(1), 1_000_000_000, accuracy: 1)
    }

    func testEmptyAndNaN() {
        let r = ValueRange(sets: sets([]), metric: metrics.byId("tracks"))
        XCTAssertTrue(r.isEmpty)
        XCTAssertTrue(r.norm(3).isNaN)
        let full = ValueRange(sets: sets([1, 2]), metric: metrics.byId("tracks"))
        XCTAssertTrue(full.norm(.nan).isNaN)
    }

    func testAxisFitLabelsTheEdges() {
        var axis = Axis(metric: metrics.byId("tracks"))
        axis.fit(sets([30, 2, 15]))
        XCTAssertEqual(axis.loText, "2"); XCTAssertEqual(axis.hiText, "30")
        axis.clear()
        XCTAssertEqual(axis.loText, ""); XCTAssertTrue(axis.range.isEmpty)
        axis.fit([])
        XCTAssertEqual(axis.hiText, "")
    }
}

final class StatPaletteTests: XCTestCase {
    func testGradientsAreUpstreams() {
        XCTAssertEqual(Palette.gradients.map(\.id), ["nebula", "ocean"])
        XCTAssertEqual(Palette.gradient(id: "nope").id, "nebula")
    }

    func testEndpointsAreTheAnchorColours() {
        let g = Palette.gradients[0]
        XCTAssertEqual(Palette.sample(g, 0), RGB8(0x4C, 0x63, 0xFF))
        XCTAssertEqual(Palette.sample(g, 1), RGB8(0xFF, 0xC8, 0x4D))
        XCTAssertEqual(Palette.sample(g, -3), Palette.sample(g, 0), "clamped")
        XCTAssertEqual(Palette.sample(g, 9), Palette.sample(g, 1))
        XCTAssertEqual(Palette.sample(g, .nan), Palette.noData)
    }

    func testStopsAreReachedExactly() {
        let g = Palette.gradients[1]
        XCTAssertEqual(Palette.sample(g, 0.5), g.stops[2])
        XCTAssertEqual(Palette.sample(g, 0.25), g.stops[1])
    }

    func testLabMixingKeepsTheMiddleClean() {
        // Half way between two saturated colours is not the grey an RGB blend would give.
        let a = RGB8(0x4C, 0x63, 0xFF), b = RGB8(0xFF, 0xC8, 0x4D)
        let mid = Palette.sample(StatGradient(id: "t", title: .gradientNebula, stops: [a, b]), 0.5)
        let rgbMid = RGB8((a.r + b.r) / 2, (a.g + b.g) / 2, (a.b + b.b) / 2)
        func chroma(_ c: RGB8) -> Double { let l = Palette.lab(c); return hypot(l.a, l.b) }
        XCTAssertGreaterThan(chroma(mid), chroma(rgbMid))
    }

    func testLabRoundTrip() {
        for c in [RGB8(0, 0, 0), RGB8(255, 255, 255), RGB8(0x9B, 0x5C, 0xFF), RGB8(12, 200, 90)] {
            let l = Palette.lab(c)
            let back = Palette.rgb(l: l.l, a: l.a, b: l.b)
            XCTAssertLessThanOrEqual(abs(back.r - c.r), 1); XCTAssertLessThanOrEqual(abs(back.g - c.g), 1)
            XCTAssertLessThanOrEqual(abs(back.b - c.b), 1)
        }
    }

    func testKeyHueFollowsTheCircleOfFifths() {
        XCTAssertEqual(Palette.key(root: 0, scaleIndex: 0), Palette.fromHSV(h: 0, s: 0.58, v: 1))
        // G is a fifth above C: 30° away; D (two fifths): 60°.
        XCTAssertEqual(Palette.key(root: 7, scaleIndex: 0), Palette.fromHSV(h: 30, s: 0.58, v: 1))
        XCTAssertEqual(Palette.key(root: 2, scaleIndex: 0), Palette.fromHSV(h: 60, s: 0.58, v: 1))
        for minor in [1, 2, 5] {
            XCTAssertEqual(Palette.key(root: 0, scaleIndex: minor), Palette.fromHSV(h: 0, s: 0.80, v: 0.82))
        }
        XCTAssertEqual(Palette.key(root: -1, scaleIndex: 0), Palette.unknown)
        XCTAssertEqual(Palette.key(root: 12, scaleIndex: 0), Palette.unknown)
    }

    func testClassColoursSpreadByGoldenAngle() {
        XCTAssertEqual(Palette.classColor(-1), Palette.unknown)
        XCTAssertNotEqual(Palette.classColor(0), Palette.classColor(1))
        XCTAssertEqual(Palette.classColor(3), Palette.classColor(3))
        XCTAssertEqual(Set((0..<12).map { Palette.classColor($0).packed }).count, 12)
    }

    func testHSVPrimaries() {
        XCTAssertEqual(Palette.fromHSV(h: 0, s: 1, v: 1), RGB8(255, 0, 0))
        XCTAssertEqual(Palette.fromHSV(h: 120, s: 1, v: 1), RGB8(0, 255, 0))
        XCTAssertEqual(Palette.fromHSV(h: 240, s: 1, v: 1), RGB8(0, 0, 255))
        XCTAssertEqual(Palette.fromHSV(h: -120, s: 1, v: 1), RGB8(0, 0, 255), "negative hue wraps")
    }
}
