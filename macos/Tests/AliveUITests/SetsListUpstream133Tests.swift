import XCTest
import AliveCore
@testable import AliveUI

/// The Sets list after upstream 1.3.1-1.3.3 (9ce4b4b, a6c8dc1, 0bb4915).
@MainActor
final class SetsListUpstream133Tests: XCTestCase {
    override func setUp() async throws {
        Localizer.shared.preference = .en
    }

    private func entry(_ name: String, dir: String = "/lib/A Project", day: Int = 1, hour: Int = 12) -> SetEntry {
        var s = SetEntry()
        s.path = dir + "/" + name + ".als"
        s.name = name
        s.projectName = "P"
        s.modified = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: 5))!
        return s
    }

    private func pipeline(_ sets: [SetEntry], _ configure: (inout SetsPipeline.Input) -> Void = { _ in }) -> SetsPipeline {
        var input = SetsPipeline.Input(sets: sets)
        configure(&input)
        return SetsPipeline.make(input)
    }

    func testSearchIsTheSharedRuleSoTagsNotesPluginsAndRendersFindASet() {
        var tagged = entry("one", dir: "/lib/Tagged Project")
        tagged.projectName = "Tagged"
        var plugged = entry("two", dir: "/lib/Plugged Project")
        plugged.plugins = ["Serum"]
        var rendered = entry("three", dir: "/lib/Rendered Project")
        rendered.renderNames = ["demo bounce"]
        let noted = entry("four", dir: "/lib/Noted Project")
        let all = [tagged, plugged, rendered, noted]

        func found(_ query: String) -> [String] {
            pipeline(all) {
                $0.query = " \(query) "
                $0.tagsOf = { $0 == tagged.projectDir ? ["Vocals"] : [] }
                $0.noteOf = { $0 == noted.projectDir ? "fix the bridge" : "" }
            }.heads.map(\.name)
        }
        XCTAssertEqual(found("vocals"), ["one"])
        XCTAssertEqual(found("serum"), ["two"])
        XCTAssertEqual(found("bounce"), ["three"])
        XCTAssertEqual(found("bridge"), ["four"])
        // Every word must hit some field (not necessarily the same one); full width counts as half.
        XCTAssertEqual(found("tagged vocals"), ["one"])
        XCTAssertEqual(found("tagged serum"), [])
        XCTAssertEqual(found("ｓｅｒｕｍ"), ["two"])
    }

    func testFilterCounterIsTheNumberOfRowsTheListShows() {
        // Two versions of one folder pass the search; with versions folded that is one project.
        let sets = [entry("song v1", day: 1), entry("song v2", day: 2), entry("beat", dir: "/lib/B Project")]
        let grouped = pipeline(sets) { $0.query = "song" }
        XCTAssertEqual(grouped.heads.count, 1)
        XCTAssertEqual(SetFormat.matches(grouped.heads.count, perProject: true), "1 project matches")

        let flat = pipeline(sets) { $0.query = "song"; $0.groupByFolder = false }
        XCTAssertEqual(SetFormat.matches(flat.heads.count, perProject: false), "2 sets match")
        XCTAssertEqual(SetFormat.matches(1, perProject: false), "1 set matches")
    }

    func testAVersionShowsItsTimeOnlyWhenAnotherVersionWasSavedTheSameDay() {
        let morning = entry("v1", day: 7, hour: 9), evening = entry("v2", day: 7, hour: 21)
        let nextDay = entry("v3", day: 8, hour: 9)
        let all = [morning, evening, nextDay]
        XCTAssertEqual(SetFormat.versionStamp(morning, among: all), "2026-03-07 09:05")
        XCTAssertEqual(SetFormat.versionStamp(evening, among: all), "2026-03-07 21:05")
        XCTAssertEqual(SetFormat.versionStamp(nextDay, among: all), "2026-03-08")
    }

    func testHomeAndEndPickTheFirstAndLastRowIncludingAnOpenFoldersVersions() {
        let sets = [entry("a2", dir: "/lib/A Project", day: 2), entry("a1", dir: "/lib/A Project", day: 1),
                    entry("b", dir: "/lib/B Project", day: 3)]
        let p = pipeline(sets)          // newest first: b, a2 (a1 folded under it)
        XCTAssertEqual(p.edge(first: true, expanded: [])?.name, "b")
        XCTAssertEqual(p.edge(first: false, expanded: [])?.name, "a2")
        let open: Set<String> = [SetsPipeline.key(forDirectory: "/lib/A Project")]
        XCTAssertEqual(p.edge(first: false, expanded: open)?.name, "a1")
        XCTAssertNil(pipeline([]).edge(first: true, expanded: []))
    }

    func testThePinnedStarIsShownOnlyWhileARowOfTheListIsPinned() {
        let p = pipeline([entry("a"), entry("b", dir: "/lib/B Project")])
        XCTAssertFalse(p.hasPinnedRows(pins: []))
        XCTAssertFalse(p.hasPinnedRows(pins: ["/lib/Elsewhere/x.als"]))
        XCTAssertTrue(p.hasPinnedRows(pins: ["/LIB/b project/b.als"]))
    }

    func testTheShownSummaryUsesSingularForms() {
        XCTAssertEqual(SetFormat.shownSummary(projects: 553, sets: 754), "553 projects · 754 sets")
        XCTAssertEqual(SetFormat.shownSummary(projects: 1, sets: 3), "1 project · 3 sets")
        XCTAssertEqual(SetFormat.shownSummary(projects: 1, sets: 1), "1 project · 1 set")
    }
}
