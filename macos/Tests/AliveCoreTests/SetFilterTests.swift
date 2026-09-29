import XCTest
@testable import AliveCore

final class SetFilterTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func set(_ name: String, creator: String = "Ableton Live 12.1", modified: Date = Date(timeIntervalSince1970: 1_700_000_000),
                     tracks: Int = 4, plugins: Int = 0, missingPlugins: Int = 0, missingFiles: Int = 0,
                     error: String = "", root: Int = -1, scale: Int = -1, renders: Bool = false,
                     dir: String = "/p/A Project") -> SetEntry {
        var s = SetEntry()
        s.path = dir + "/" + name + ".als"
        s.name = name
        s.creator = creator
        s.modified = modified
        s.tracks = tracks
        s.plugins = (0..<plugins).map { "P\($0)" }
        s.missingPlugins = missingPlugins
        s.missingFiles = missingFiles
        s.error = error
        s.scaleRoot = root
        s.scaleIndex = scale
        s.hasRenders = renders
        return s
    }

    private let noTags: (String) -> [String] = { _ in [] }

    private func hits(_ f: SetFilter, _ sets: [SetEntry], tags: @escaping (String) -> [String] = { _ in [] }) -> [String] {
        sets.filter { f.matches($0, tagsOf: tags) }.map(\.name)
    }

    func testEmptyFilterMatchesEverythingAndCountsNothing() {
        let f = SetFilter()
        XCTAssertTrue(f.isEmpty)
        XCTAssertEqual(f.activeCount, 0)
        XCTAssertTrue(f.matches(set("a"), tagsOf: noTags))
    }

    func testDateRangeIsInclusive() {
        let d1 = Date(timeIntervalSince1970: 1_000), d2 = Date(timeIntervalSince1970: 2_000), d3 = Date(timeIntervalSince1970: 3_000)
        let sets = [set("a", modified: d1), set("b", modified: d2), set("c", modified: d3)]
        var f = SetFilter()
        f.from = d2
        XCTAssertEqual(hits(f, sets), ["b", "c"])
        f.to = d2
        XCTAssertEqual(hits(f, sets), ["b"])
        XCTAssertEqual(f.activeCount, 1)
    }

    func testVersionsAreOrOfTheSelected() {
        let sets = [set("a", creator: "Ableton Live 12.1"), set("b", creator: "Ableton Live 11.3.4"), set("c", creator: "Ableton Live 10.1")]
        var f = SetFilter()
        f.versions = ["12.1", "10.1"]
        XCTAssertEqual(hits(f, sets), ["a", "c"])
    }

    func testKeyRootsIncludingNoKeyAndAnyKey() {
        let sets = [set("c", root: 0), set("d", root: 2), set("none", root: -1)]
        var f = SetFilter()
        f.keyRoots = [0]
        XCTAssertEqual(hits(f, sets), ["c"])
        f.keyRoots = [SetFilter.noKey]
        XCTAssertEqual(hits(f, sets), ["none"])
        f.keyRoots = [SetFilter.anyKey]
        XCTAssertEqual(hits(f, sets), ["c", "d"])
        f.keyRoots = [SetFilter.anyKey, SetFilter.noKey]
        XCTAssertEqual(hits(f, sets), ["c", "d", "none"])
    }

    func testKeyScalesAndRootsCountAsOneGroup() {
        let sets = [set("maj", root: 0, scale: 0), set("min", root: 0, scale: 1)]
        var f = SetFilter()
        f.keyScales = [1]
        XCTAssertEqual(hits(f, sets), ["min"])
        f.keyRoots = [0]
        XCTAssertEqual(f.activeCount, 1)
    }

    func testTagsAreLookedUpByProjectFolder() {
        let sets = [set("a", dir: "/p/One Project"), set("b", dir: "/p/Two Project")]
        let tags: (String) -> [String] = { $0 == "/p/One Project" ? ["drum", "vocal"] : ["synth"] }
        var f = SetFilter()
        f.tags = ["vocal", "bass"]
        XCTAssertEqual(hits(f, sets, tags: tags), ["a"])
        f.tags = ["synth"]
        XCTAssertEqual(hits(f, sets, tags: tags), ["b"])
    }

    func testTrackAndPluginCountBounds() {
        let sets = [set("s", tracks: 2, plugins: 0), set("m", tracks: 8, plugins: 3), set("l", tracks: 30, plugins: 12)]
        var f = SetFilter()
        f.tracksMin = 5
        XCTAssertEqual(hits(f, sets), ["m", "l"])
        f.tracksMax = 10
        XCTAssertEqual(hits(f, sets), ["m"])
        f = SetFilter()
        f.pluginsMin = 1
        f.pluginsMax = 5
        XCTAssertEqual(hits(f, sets), ["m"])
        XCTAssertEqual(f.activeCount, 1)
    }

    func testPluginStateToggles() {
        let sets = [set("ok", plugins: 2), set("holes", plugins: 2, missingPlugins: 1)]
        var f = SetFilter()
        f.pluginsMissingOnly = true
        XCTAssertEqual(hits(f, sets), ["holes"])
        f = SetFilter()
        f.pluginsAllInstalled = true
        XCTAssertEqual(hits(f, sets), ["ok"])
    }

    func testFileStateIsAnyOfTheChecked() {
        let sets = [set("whole"), set("lost", missingFiles: 2), set("broken", missingFiles: 3, error: "bad gzip")]
        var f = SetFilter()
        f.filesComplete = true
        XCTAssertEqual(hits(f, sets), ["whole"])
        f.filesMissing = true
        XCTAssertEqual(hits(f, sets), ["whole", "lost"])
        f = SetFilter()
        f.filesUnreadable = true
        XCTAssertEqual(hits(f, sets), ["broken"])   // an unreadable set is not "missing" even with holes
    }

    func testRenders() {
        let sets = [set("with", renders: true), set("without")]
        var f = SetFilter()
        f.previewHasRenders = true
        XCTAssertEqual(hits(f, sets), ["with"])
        f.previewHasRenders = false
        f.previewNoRenders = true
        XCTAssertEqual(hits(f, sets), ["without"])
        f.previewHasRenders = true
        XCTAssertEqual(hits(f, sets), ["with", "without"])
    }

    func testActiveCountCountsGroupsNotFields() {
        var f = SetFilter()
        f.from = Date(); f.to = Date()
        f.versions = ["12.1"]
        f.tags = ["x"]
        f.tracksMin = 1; f.tracksMax = 2
        f.pluginsMissingOnly = true; f.pluginsMin = 1
        f.filesComplete = true; f.filesMissing = true
        f.previewHasRenders = true
        f.keyRoots = [1]; f.keyScales = [1]
        XCTAssertEqual(f.activeCount, 8)
        f.clear()
        XCTAssertTrue(f.isEmpty)
        XCTAssertEqual(f, SetFilter())
    }

    func testIgnoringLeavesOneGroupOut() {
        var f = SetFilter()
        f.versions = ["10.1"]
        f.pluginsMissingOnly = true
        let s = set("a", creator: "Ableton Live 12.1", plugins: 1)
        XCTAssertFalse(f.matches(s, tagsOf: noTags))
        XCTAssertFalse(f.matches(s, tagsOf: noTags, ignoring: .versions))
        XCTAssertFalse(f.matches(s, tagsOf: noTags, ignoring: .pluginsState))
        XCTAssertTrue(f.matches(s, tagsOf: noTags, ignoring: [.versions, .pluginsState]))
    }

    // MARK: dates and counts

    func testParseDateGranularity() {
        let c = utc
        XCTAssertEqual(SetFilter.formatDate(SetFilter.parseDate("2026", upperBound: false, calendar: c), calendar: c), "2026-01-01")
        XCTAssertEqual(SetFilter.formatDate(SetFilter.parseDate("2026-08", upperBound: false, calendar: c), calendar: c), "2026-08-01")
        let endYear = SetFilter.parseDate("2026", upperBound: true, calendar: c)!
        XCTAssertEqual(c.dateComponents([.month, .day, .hour, .minute, .second], from: endYear),
                       DateComponents(month: 12, day: 31, hour: 23, minute: 59, second: 59))
        let endFeb = SetFilter.parseDate("2024/02", upperBound: true, calendar: c)!
        XCTAssertEqual(c.component(.day, from: endFeb), 29)
        let endDay = SetFilter.parseDate("2026.08.07", upperBound: true, calendar: c)!
        XCTAssertEqual(SetFilter.formatDate(endDay, calendar: c), "2026-08-07")
        XCTAssertEqual(c.component(.hour, from: endDay), 23)
    }

    func testParseDateRejectsJunk() {
        let c = utc
        for bad in ["", "  ", "abc", "1800", "2026-13", "2026-02-30", "2026-00", "2026-1-0", nil] as [String?] {
            XCTAssertNil(SetFilter.parseDate(bad, upperBound: false, calendar: c), "\(bad ?? "nil")")
        }
        XCTAssertNil(SetFilter.parseDate("2026-02-30", upperBound: true, calendar: c))
        XCTAssertEqual(SetFilter.formatDate(nil), "")
    }

    func testParseCount() {
        XCTAssertEqual(SetFilter.parseCount(" 12 "), 12)
        XCTAssertEqual(SetFilter.parseCount("0"), 0)
        XCTAssertEqual(SetFilter.parseCount("-3"), -1)
        XCTAssertEqual(SetFilter.parseCount("x"), -1)
        XCTAssertEqual(SetFilter.parseCount(nil), -1)
        XCTAssertEqual(SetFilter.formatCount(-1), "")
        XCTAssertEqual(SetFilter.formatCount(7), "7")
    }

    func testCompareVersionIsNumeric() {
        XCTAssertEqual(SetFilter.compareVersion("12.4.3", "12.10"), .orderedAscending)
        XCTAssertEqual(SetFilter.compareVersion("11.3", "10.9.9"), .orderedDescending)
        XCTAssertEqual(SetFilter.compareVersion("12.0b3", "12.0"), .orderedDescending)   // equal numbers: text decides
        XCTAssertEqual(SetFilter.compareVersion("", "1"), .orderedAscending)
        XCTAssertEqual(SetFilter.compareVersion("12.1", "12.1"), .orderedSame)
    }

    // MARK: facets

    func testFacetsListOnlyWhatOccursAndGreyWhatWouldBeEmpty() {
        let sets = [
            set("a", creator: "Ableton Live 12.1", root: 0, scale: 0, dir: "/p/One Project"),
            set("b", creator: "Ableton Live 10.1", root: -1, dir: "/p/Two Project"),
            set("c", creator: "Ableton Live 12.1", missingPlugins: 1, root: 2, scale: 1, renders: true, dir: "/p/Three Project"),
        ]
        let tags: (String) -> [String] = { $0.contains("One") ? ["zed"] : $0.contains("Three") ? ["alpha", "zed"] : [] }
        var f = SetFilter()
        f.versions = ["10.1"]
        let x = SetFilterFacets.make(sets: sets, filter: f, tagsOf: tags)
        XCTAssertEqual(x.versions, ["12.1", "10.1"])
        XCTAssertEqual(x.roots, [SetFilter.anyKey, SetFilter.noKey, 0, 2])
        XCTAssertEqual(x.scales, [0, 1])
        XCTAssertEqual(x.tags, ["alpha", "zed"])
        XCTAssertEqual(x.matches, 1)
        // Versions are judged without their own group: both stay possible.
        XCTAssertTrue(x.disabledVersions.isEmpty)
        // Only "b" (no key, no scale, no tags) passes the version filter.
        XCTAssertEqual(x.disabledRoots, [SetFilter.anyKey, 0, 2])
        XCTAssertEqual(x.disabledScales, [0, 1])
        XCTAssertEqual(x.disabledTags, ["alpha", "zed"])
        XCTAssertFalse(x.canPickMissingPlugins)
        XCTAssertTrue(x.canPickAllInstalled)
        XCTAssertTrue(x.canPickComplete)
        XCTAssertFalse(x.canPickMissingFiles)
        XCTAssertFalse(x.canPickUnreadable)
        XCTAssertFalse(x.canPickHasRenders)
        XCTAssertTrue(x.canPickNoRenders)
    }

    func testFacetsForAnEmptyCatalog() {
        let x = SetFilterFacets.make(sets: [], filter: SetFilter(), tagsOf: noTags)
        XCTAssertTrue(x.versions.isEmpty)
        XCTAssertTrue(x.roots.isEmpty)
        XCTAssertEqual(x.matches, 0)
    }
}
