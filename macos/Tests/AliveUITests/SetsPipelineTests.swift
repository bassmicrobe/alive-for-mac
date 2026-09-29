import XCTest
import AliveCore
@testable import AliveUI

final class SetsPipelineTests: XCTestCase {
    private func entry(_ name: String, dir: String = "/lib/A Project", modified: TimeInterval = 1_000,
                       tempo: Double = 120, missingPlugins: Int = 0, plugins: Int = 0, key: String = "") -> SetEntry {
        var s = SetEntry()
        s.path = dir + "/" + name + ".als"
        s.name = name
        s.projectName = "P"
        s.creator = "Ableton Live 12.1"
        s.modified = Date(timeIntervalSince1970: modified)
        s.tempo = tempo
        s.plugins = (0..<plugins).map { "P\($0)" }
        s.missingPlugins = missingPlugins
        s.key = key
        return s
    }

    private func make(_ sets: [SetEntry], _ configure: (inout SetsPipeline.Input) -> Void = { _ in }) -> SetsPipeline {
        var input = SetsPipeline.Input(sets: sets)
        configure(&input)
        return SetsPipeline.make(input)
    }

    func testRowIndexFollowsDisplayOrderPinnedFirstAndUnfoldedChildren() {
        let dirA = "/lib/A Project", dirB = "/lib/B Project", dirC = "/lib/C Project"
        let sets = [entry("a2", dir: dirA, modified: 300), entry("a1", dir: dirA, modified: 100),
                    entry("b", dir: dirB, modified: 200), entry("c", dir: dirC, modified: 50)]
        let pinned = dirC + "/c.als"
        let p = make(sets) { $0.pinnedFirst = true; $0.pins = [pinned] }
        let open: Set<String> = [SetsPipeline.key(forDirectory: dirA)]
        // c (pinned), a2, a1 (unfolded under a2), b
        XCTAssertEqual(p.rowIndex(of: pinned, expanded: open), 0)
        XCTAssertEqual(p.rowIndex(of: dirA + "/a2.als", expanded: open), 1)
        XCTAssertEqual(p.rowIndex(of: dirA + "/a1.als", expanded: open), 2)
        XCTAssertEqual(p.rowIndex(of: dirB + "/b.als", expanded: open), 3)
        // Folded: the child has no row, and the rows after it move up.
        XCTAssertNil(p.rowIndex(of: dirA + "/a1.als", expanded: []))
        XCTAssertEqual(p.rowIndex(of: dirB + "/b.als", expanded: []), 2)
    }

    func testFoldsAFolderUnderItsNewestSetAndListsTheRestNewestFirst() {
        let sets = [entry("v1", modified: 100), entry("v3", modified: 300), entry("v2", modified: 200),
                    entry("other", dir: "/lib/B Project", modified: 50)]
        let p = make(sets)
        XCTAssertEqual(p.heads.map(\.name), ["v3", "other"])
        XCTAssertEqual(p.heads.first?.collapsedCount, 2)
        XCTAssertEqual(p.hidden[SetsPipeline.key(forDirectory: "/lib/A Project")]?.map(\.name), ["v2", "v1"])
        XCTAssertNil(p.hidden[SetsPipeline.key(forDirectory: "/lib/B Project")])
    }

    func testFiltersBeforeFoldingSoAnOlderVersionCanBeTheHead() {
        var old = entry("old", modified: 100, tempo: 90)
        old.tracks = 2
        var new = entry("new", modified: 300, tempo: 120)
        new.tracks = 10
        let sets = [old, new]
        var filter = SetFilter()
        filter.tracksMax = 3
        let p = make(sets) { $0.filter = filter }
        XCTAssertEqual(p.heads.map(\.name), ["old"])
        XCTAssertEqual(p.heads.first?.collapsedCount, 0)
        XCTAssertTrue(p.hidden.isEmpty)
    }

    func testHiddenVersionsAreOnlyWhatPassedTheSearch() {
        let sets = [entry("song final", modified: 300), entry("song draft", modified: 200), entry("beat", modified: 100)]
        let p = make(sets) { $0.query = "song" }
        XCTAssertEqual(p.heads.map(\.name), ["song final"])
        XCTAssertEqual(p.hidden.values.flatMap { $0 }.map(\.name), ["song draft"])
    }

    func testNotGroupingKeepsEverySetAndResetsTheCounter() {
        var a = entry("a", modified: 100)
        a.collapsedCount = 5
        let p = make([a, entry("b", modified: 200)]) { $0.groupByFolder = false }
        XCTAssertEqual(p.heads.count, 2)
        XCTAssertTrue(p.heads.allSatisfy { $0.collapsedCount == 0 })
        XCTAssertTrue(p.hidden.isEmpty)
    }

    func testDefaultOrderIsNewestFirst() {
        let sets = [entry("a", dir: "/x/1", modified: 1), entry("b", dir: "/x/2", modified: 3), entry("c", dir: "/x/3", modified: 2)]
        XCTAssertEqual(make(sets).heads.map(\.name), ["b", "c", "a"])
    }

    func testSortColumnAndDirection() {
        let sets = [entry("a", dir: "/x/1", tempo: 100), entry("b", dir: "/x/2", tempo: 140), entry("c", dir: "/x/3", tempo: 120)]
        XCTAssertEqual(make(sets) { $0.sort = SetSort(column: .bpm, descending: false) }.heads.map(\.name), ["a", "c", "b"])
        XCTAssertEqual(make(sets) { $0.sort = SetSort(column: .bpm, descending: true) }.heads.map(\.name), ["b", "c", "a"])
    }

    func testEmptyKeysAlwaysGoLastInBothDirections() {
        let sets = [entry("none", dir: "/x/1"), entry("c", dir: "/x/2", key: "C Major"), entry("a", dir: "/x/3", key: "A Minor")]
        XCTAssertEqual(make(sets) { $0.sort = SetSort(column: .key, descending: false) }.heads.map(\.name), ["a", "c", "none"])
        // Descending reverses the comparison, so the empties come first there (upstream reverses `chosen(b, a)`).
        XCTAssertEqual(make(sets) { $0.sort = SetSort(column: .key, descending: true) }.heads.map(\.name).first, "none")
    }

    func testPinnedFirstIsOnlyTheFirstKey() {
        let sets = [entry("a", dir: "/x/1", modified: 1), entry("b", dir: "/x/2", modified: 3),
                    entry("c", dir: "/x/3", modified: 2), entry("d", dir: "/x/4", modified: 4)]
        let pins: Set<String> = ["/X/1/A.als", sets[2].path]      // case does not matter
        let p = make(sets) { $0.pinnedFirst = true; $0.pins = pins; $0.sort = SetSort(column: .modified, descending: true) }
        XCTAssertEqual(p.heads.map(\.name), ["c", "a", "d", "b"])
        // Reversing the sort reverses inside the groups but keeps the pinned group on top.
        let q = make(sets) { $0.pinnedFirst = true; $0.pins = pins; $0.sort = SetSort(column: .modified, descending: false) }
        XCTAssertEqual(q.heads.map(\.name), ["a", "c", "b", "d"])
        let off = make(sets) { $0.pinnedFirst = false; $0.pins = pins }
        XCTAssertEqual(off.heads.map(\.name), ["d", "b", "c", "a"])
    }

    func testTagsColumnSortsUntaggedLast() {
        let sets = [entry("plain", dir: "/x/1"), entry("tagged", dir: "/x/2")]
        let tags: (String) -> [String] = { $0 == "/x/2" ? ["drum"] : [] }
        let p = make(sets) { $0.sort = SetSort(column: .tags, descending: false); $0.tagsOf = tags }
        XCTAssertEqual(p.heads.map(\.name), ["tagged", "plain"])
    }

    func testFlattenedFollowsOpenFolders() {
        let sets = [entry("v1", modified: 100), entry("v2", modified: 200), entry("o", dir: "/lib/B Project", modified: 50)]
        let p = make(sets)
        XCTAssertEqual(p.flattened(expanded: []).map(\.name), ["v2", "o"])
        XCTAssertEqual(p.flattened(expanded: [SetsPipeline.key(forDirectory: "/lib/A Project")]).map(\.name), ["v2", "v1", "o"])
        XCTAssertEqual(p.head(containing: sets[0].path)?.name, "v2")
        XCTAssertEqual(p.head(containing: sets[1].path)?.name, "v2")
        XCTAssertNil(p.head(containing: "/nope.als"))
    }

    // MARK: plugin status unknown

    func testUnknownPluginStatusIgnoresThePluginStateFilters() {
        let sets = [entry("holes", dir: "/x/1", missingPlugins: 2, plugins: 2), entry("fine", dir: "/x/2", plugins: 2)]
        var filter = SetFilter()
        filter.pluginsMissingOnly = true
        XCTAssertEqual(make(sets) { $0.filter = filter; $0.pluginsKnown = true }.heads.map(\.name), ["holes"])
        // The installed list could not be read: "missing" is not a fact, so the toggle filters nothing.
        XCTAssertEqual(Set(make(sets) { $0.filter = filter; $0.pluginsKnown = false }.heads.map(\.name)), ["holes", "fine"])
        // A count range is a fact about the set, not about the machine, and still applies.
        filter.pluginsMin = 3
        XCTAssertTrue(make(sets) { $0.filter = filter; $0.pluginsKnown = false }.heads.isEmpty)
    }

    func testEffectiveFilterCountsWithoutTheUnknownToggles() {
        var filter = SetFilter()
        filter.pluginsAllInstalled = true
        XCTAssertEqual(SetsPipeline.effectiveFilter(filter, pluginsKnown: true).activeCount, 1)
        XCTAssertEqual(SetsPipeline.effectiveFilter(filter, pluginsKnown: false).activeCount, 0)
    }
}
