import SwiftUI
import XCTest
import AliveCore
@testable import AliveUI

@MainActor
final class SetsModelTests: XCTestCase {
    func testRowsFollowSearchAndFilterAndShownCount() throws {
        let app = try makeModel()
        XCTAssertEqual(app.sets.rows.count, 0)
        XCTAssertEqual(app.sets.shownCount, 0)
        XCTAssertEqual(app.sets.activeFilterCount, 0)
        app.sets.filter.versions = ["12.1"]
        XCTAssertEqual(app.sets.activeFilterCount, 1)
        app.sets.filter.clear()
        XCTAssertEqual(app.sets.activeFilterCount, 0)
    }

    func testPluginStatusIsUnknownWithAnEmptyInventory() throws {
        let app = try makeModel()
        XCTAssertFalse(app.sets.pluginsKnown, "the stub inventory is empty")
        app.sets.filter.pluginsMissingOnly = true
        XCTAssertEqual(app.sets.activeFilterCount, 0, "an unknowable condition is not counted on the Filters button")
        app.sets.filter.tracksMin = 2
        XCTAssertEqual(app.sets.activeFilterCount, 1)
    }

    func testSelectSetsTheAppSelectionAndBumpsTheScrollRequest() throws {
        let app = try makeModel()
        let before = app.sets.scrollRequest.serial
        app.sets.select(path: "/x/a.als")
        XCTAssertEqual(app.selectedSetPath, "/x/a.als")
        XCTAssertEqual(app.sets.scrollRequest, SetsModel.ScrollRequest(path: "/x/a.als", serial: before + 1))
        app.sets.select(path: nil)
        XCTAssertNil(app.selectedSetPath)
    }

    func testFoldExpansionIsPerFolderAndCaseInsensitive() throws {
        let app = try makeModel()
        XCTAssertFalse(app.sets.isExpanded("/Lib/A Project"))
        app.sets.setExpanded("/Lib/A Project", true)
        XCTAssertTrue(app.sets.isExpanded("/lib/a project"))
        app.sets.setExpanded("/lib/a project", false)
        XCTAssertFalse(app.sets.isExpanded("/Lib/A Project"))
    }

    func testPinnedFirstGoesThroughSettings() throws {
        let app = try makeModel()
        XCTAssertFalse(app.settings.pinnedFirst)
        app.sets.setPinnedFirst(true)
        XCTAssertTrue(app.settings.pinnedFirst)
        XCTAssertTrue(AppSettings.load(dir: app.dataDir).pinnedFirst)
    }

    func testTagsAreKeyedByProjectFolderAndBumpTheRevision() async throws {
        let app = try makeModel()
        var a = SetEntry(), b = SetEntry()
        a.path = "/lib/Song Project/v1.als"
        b.path = "/lib/Song Project/v2.als"
        let before = app.sets.metaRevision
        app.sets.meta.set(a.projectDir, tags: ["drum", "vocal"], note: "keep the bridge")
        XCTAssertEqual(app.sets.tags(of: b), ["drum", "vocal"], "a project's versions share their tags")
        XCTAssertEqual(app.sets.note(of: b), "keep the bridge")
        for _ in 0..<50 where app.sets.metaRevision == before { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertGreaterThan(app.sets.metaRevision, before)
        // Written where upstream writes them.
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.dataDir + "/notes.cfg"))
    }

    func testColumnLayoutIsSavedToItsOwnFileAndReadBack() async throws {
        let app = try makeModel()
        app.sets.columnCustomization[visibility: SetColumnID.key.id] = .visible
        app.sets.sortOrder = [SetSortComparator(.bpm, order: .reverse)]
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: app.dataDir + "/sets-columns.json") {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let reloaded = AppModel(dataDir: app.dataDir)
        XCTAssertEqual(reloaded.sets.columnCustomization[visibility: SetColumnID.key.id], .visible)
        XCTAssertEqual(reloaded.sets.sort, SetSort(column: .bpm, descending: true))
        reloaded.sets.resetColumns()
        XCTAssertNil(reloaded.sets.sort)
    }

    func testTheCatalogWatcherStartsOnceAndStops() throws {
        let app = try makeModel()
        app.sets.watcher.start()
        app.sets.watcher.start()
        app.sets.watcher.stop()
    }
}
