import XCTest
@testable import AliveCore
@testable import AliveUI

/// Home changes of upstream 1.3.1-1.3.3 (9ce4b4b, a6c8dc1, 0bb4915): one test per behaviour.
@MainActor
final class HomeUpstream133Tests: XCTestCase {
    private func entry(_ path: String, age: Double = 0, backup: Bool = false) -> SetEntry {
        var e = SetEntry()
        e.path = path
        e.name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        e.projectName = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        e.modified = Date(timeIntervalSince1970: 2_000_000_000 - age)
        e.isBackup = backup
        return e
    }

    /// An app over a scratch library with two projects, scanned.
    private func loadedApp() async throws -> AppModel {
        let scratch = makeHomeScratch()
        scratch.write("data/settings.cfg", "root=\(scratch.sub("lib"))\n")
        _ = try scratch.writeSet("lib/A Project/a.als")
        _ = try scratch.writeSet("lib/B Project/b.als")
        let app = AppModel(dataDir: scratch.sub("data"))
        app.start()
        for _ in 0..<300 where !(app.catalog.isReady && app.catalog.sets.count == 2) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(app.catalog.sets.count, 2)
        app.tab = .home
        return app
    }

    // MARK: selection

    func testSearchThatHidesTheSelectedTileClearsTheSelection() async throws {
        let app = try await loadedApp()
        let a = try XCTUnwrap(app.catalog.sets.first { $0.name == "a" }).path

        app.selectedSetPath = a
        app.searchText = "b.als"          // one word, in B's path only (every word of a query counts)
        app.home.dropHiddenSelection()
        XCTAssertNil(app.selectedSetPath, "⌘O must not open a project the search has hidden")

        app.searchText = ""
        app.selectedSetPath = a
        app.home.dropHiddenSelection()
        XCTAssertEqual(app.selectedSetPath, a, "a tile that is still shown stays selected")
    }

    func testDownFromTheSearchFieldEntersTheGridAtTheSelectedOrFirstTile() async throws {
        let app = try await loadedApp()
        let rows = app.home.rows

        app.selectedSetPath = nil
        app.home.enterFromSearch()
        XCTAssertEqual(app.selectedSetPath, rows[0].path)

        app.selectedSetPath = rows[1].path
        app.home.enterFromSearch()
        XCTAssertEqual(app.selectedSetPath, rows[1].path, "a picked tile keeps the keyboard")
        XCTAssertEqual(app.home.gridFocusRequest, 2)
    }

    func testHomeAndEndGoToTheEndsOfTheGridWithoutASelection() {
        XCTAssertEqual(TileNavigation.move(from: nil, .last, columns: 4, count: 10), 9)
        XCTAssertEqual(TileNavigation.move(from: 5, .first, columns: 4, count: 10), 0)
        XCTAssertEqual(HomeGridKeyboard.action(for: .home), .move(.first))
        XCTAssertEqual(HomeGridKeyboard.action(for: .end), .move(.last))
    }

    // MARK: search and pins

    func testHomeSearchUsesTheSetsRuleForTagsNotesAndPlugins() {
        var tagged = entry("/p/Alpha Project/alpha.als")
        tagged.plugins = ["Serum"]
        let other = entry("/p/Beta Project/beta.als")
        let sets = [tagged, other]
        func found(_ q: String) -> [String] {
            HomeListing.projects(sets: sets, query: q, groupByFolder: true, pinOrder: [], pinnedFirst: false,
                                 tagsOf: { $0 == "/p/Alpha Project" ? ["techno"] : [] }, noteOf: { _ in "" }).map(\.name)
        }
        XCTAssertEqual(found("techno"), ["alpha"], "tags are searched")
        XCTAssertEqual(found("serum"), ["alpha"], "plugins are searched")
        XCTAssertEqual(found("zzz"), [])
    }

    func testTheStarIsOfferedOnlyWhileSomethingMatchingIsPinned() {
        let sets = [entry("/p/Alpha Project/alpha.als"), entry("/p/Beta Project/beta.als", age: 5)]
        func pinned(pins: [String], query: String = "") -> Int {
            HomeListing.listing(sets: sets, query: query, groupByFolder: true, pinOrder: pins, pinnedFirst: true,
                                tagsOf: { _ in [] }, noteOf: { _ in "" }).pinned.count
        }
        XCTAssertEqual(pinned(pins: []), 0)
        XCTAssertEqual(pinned(pins: ["/p/Beta Project/beta.als"]), 1)
        XCTAssertEqual(pinned(pins: ["/p/Beta Project/beta.als"], query: "alpha"), 0, "a search that hides the pins hides the star")
    }

    // MARK: calendar

    func testDayListShowsTheNewestSetPerProjectAndKeepsAProjectThatHasGone() {
        let sets = [entry("/p/Alpha Project/alpha.als", age: 10), entry("/p/Alpha Project/alpha v2.als", age: 5),
                    entry("/p/Alpha Project/Backup/alpha [x].als", age: 1, backup: true)]
        let list = HomeDay.projects(dirs: ["/p/Alpha Project", "/p/Gone Project", "/p/alpha project/"], sets: sets)
        XCTAssertEqual(list.map(\.name), ["alpha v2", "Gone Project"], "busiest first, one entry per project")
        XCTAssertEqual(list.map(\.setPath), ["/p/Alpha Project/alpha v2.als", nil], "a project gone from the catalog has no set")
        XCTAssertTrue(HomeDay.projects(dirs: [], sets: sets).isEmpty, "a day from before the history kept projects")
    }

    // MARK: texts

    func testSingularFormsHaveTheirOwnSentence() {
        Localizer.shared.preference = .en
        defer { Localizer.shared.preference = .system }
        XCTAssertEqual(HomeStrings.projectsShown(1), "1 project shown")
        XCTAssertEqual(HomeStrings.projectsShown(12), "12 projects shown")
        XCTAssertEqual(HomeStrings.tracks(1), "1 track")
    }
}
