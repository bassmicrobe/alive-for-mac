import XCTest
@testable import AliveCore

final class PluginFilterTests: XCTestCase {
    private func mk(_ name: String, vendor: String = "", uid: String = "vst3:x", sets: Int = 1, match: MatchKind = .exact,
                      kind: PluginKind = .vst3, category: String = "", installed: Bool = true) -> PluginStat {
        var st = PluginStat()
        st.name = name; st.vendor = vendor; st.uid = uid; st.sets = sets; st.match = match
        if installed {
            var p = InstalledPlugin(); p.name = name; p.kind = kind; p.category = category
            st.installed = p
        }
        return st
    }

    private var sample: [PluginStat] {
        [
            mk("Pro-Q 3", vendor: "FabFilter", sets: 103, kind: .vst3, category: "Fx|EQ"),
            mk("Serum", vendor: "Xfer Records", uid: "vst2:1", sets: 19, kind: .vst2, category: "Instrument|Synth"),
            mk("Falcon", vendor: "UVI", uid: "au:aumu:falc:uvi ", sets: 4, kind: .audioUnit, category: "Instrument"),
            mk("Gone Plugin", uid: "vst3:gone", sets: 7, match: .missing, installed: false),
            mk("Twin", vendor: "FabFilter", uid: "vst2:2", sets: 2, match: .otherFormat, kind: .vst3, category: "Fx"),
            mk("Idle", vendor: "Someone", sets: 0, kind: .vst3, category: "Fx|Reverb"),
        ]
    }

    private func names(_ f: PluginFilter) -> [String] { sample.filter { f.matches($0) }.map(\.name) }

    func testEmptyFilterMatchesEverythingAndCountsNothing() {
        let f = PluginFilter()
        XCTAssertTrue(f.isEmpty)
        XCTAssertEqual(f.activeCount, 0)
        XCTAssertEqual(names(f).count, 6)
    }

    func testStatusIsAnOrOfTheTickedStates() {
        var f = PluginFilter()
        f.statusMissing = true
        XCTAssertEqual(names(f), ["Gone Plugin"])
        f.statusOtherFormat = true
        XCTAssertEqual(names(f), ["Gone Plugin", "Twin"])
        f.statusInstalled = true
        XCTAssertEqual(names(f).count, 6)
        XCTAssertEqual(f.activeCount, 1)                                     // the three tick boxes are one condition
    }

    func testFormatGroupsIncludeAUAndOther() {
        var f = PluginFilter()
        f.formats = ["AU"]
        XCTAssertEqual(names(f), ["Falcon"])
        f.formats = ["VST2"]
        XCTAssertEqual(names(f), ["Serum", "Twin"])                          // by the uid when not installed exactly
        f.formats = ["Other"]
        XCTAssertEqual(names(f), [])                                         // every plugin has a format here
        var unknown = mk("No idea", uid: "", match: .missing, installed: false)
        unknown.uid = ""
        XCTAssertEqual(PluginFilter.formatGroup(of: unknown), "Other")
        f.formats = ["VST3", "AU"]
        XCTAssertEqual(names(f), ["Pro-Q 3", "Falcon", "Gone Plugin", "Idle"])
    }

    func testVendorsAndCategoriesIgnoreCaseAndUseStandIns() {
        var f = PluginFilter()
        f.vendors = ["fabfilter"]
        XCTAssertEqual(names(f), ["Pro-Q 3", "Twin"])
        f.vendors = [PluginFilter.unknownVendor]
        XCTAssertEqual(names(f), ["Gone Plugin"])
        f.vendors = []
        f.categories = ["eq"]
        XCTAssertEqual(names(f), ["Pro-Q 3"])
        f.categories = [PluginFilter.otherCategory]
        XCTAssertEqual(names(f), ["Gone Plugin", "Twin"])                    // no type: "Fx" alone is generic
    }

    func testSetsRange() {
        var f = PluginFilter()
        f.setsMin = 5
        XCTAssertEqual(names(f), ["Pro-Q 3", "Serum", "Gone Plugin"])
        f.setsMax = 19
        XCTAssertEqual(names(f), ["Serum", "Gone Plugin"])
        f.setsMin = nil; f.setsMax = 0
        XCTAssertEqual(names(f), ["Idle"])
        XCTAssertEqual(f.activeCount, 1)
    }

    func testConditionsCombineAndClearResets() {
        var f = PluginFilter()
        f.vendors = ["FabFilter"]; f.statusOtherFormat = true; f.formats = ["VST3"]
        f.categories = ["Fx"]; f.setsMin = 1
        XCTAssertEqual(f.activeCount, 5)
        f.clear()
        XCTAssertTrue(f.isEmpty)
        XCTAssertEqual(f, PluginFilter())
        XCTAssertEqual(f.hashValue, PluginFilter().hashValue)
    }

    func testUnknownStatusPassesNoStatusFilter() {
        var f = PluginFilter()
        var st = mk("X"); st.match = .unknown
        XCTAssertTrue(f.matches(st))
        f.statusInstalled = true
        XCTAssertFalse(f.matches(st))
    }

    // MARK: facets

    func testFacetsCountWhatEachChoiceWouldLeave() {
        var f = PluginFilter()
        f.vendors = ["FabFilter"]
        let facets = PluginFacets.compute(f, over: sample)
        XCTAssertEqual(facets.matches, 2)
        // Status counts ignore the status conditions but respect the vendor.
        XCTAssertEqual(facets.installed, 1)
        XCTAssertEqual(facets.otherFormat, 1)
        XCTAssertEqual(facets.missing, 0)
        XCTAssertEqual(facets.formatCounts["VST3"], 1)
        XCTAssertEqual(facets.formatCounts["VST2"], 1)          // Twin: the set asked for a VST2
        // Vendors ignore their own condition: every vendor is still reachable.
        XCTAssertTrue(facets.canPick(vendor: "UVI"))
        XCTAssertTrue(facets.canPick(vendor: PluginFilter.unknownVendor))
        // Categories respect the vendor: "Reverb" (Someone's) is not reachable.
        XCTAssertTrue(facets.canPick(category: "EQ"))
        XCTAssertFalse(facets.canPick(category: "Reverb"))
        f.statusMissing = true
        XCTAssertEqual(PluginFacets.compute(f, over: sample).matches, 0)
    }

    func testOptionsAreSortedAndGetStandInsOnlyWhenNeeded() {
        XCTAssertEqual(PluginFacets.vendorOptions(sample), ["FabFilter", "Someone", "UVI", "Xfer Records", PluginFilter.unknownVendor])
        XCTAssertEqual(PluginFacets.categoryOptions(sample), ["Instrument", "Reverb", "Synth", "EQ"].sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } + [PluginFilter.otherCategory])
        XCTAssertEqual(PluginFacets.vendorOptions([mk("A", vendor: "Z"), mk("B", vendor: "a")]), ["a", "Z"])
        XCTAssertEqual(PluginFacets.vendorOptions([]), [])
    }
}
