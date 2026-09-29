import XCTest
@testable import AliveUI

/// A model on a scratch data folder: tests never touch the owner's settings.
@MainActor
func makeModel(files: [String: String] = [:]) throws -> AppModel {
    let dir = NSTemporaryDirectory() + "alive-ui-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, text) in files { try text.write(toFile: dir + "/" + name, atomically: true, encoding: .utf8) }
    return AppModel(dataDir: dir)
}

@MainActor
final class AppModelTests: XCTestCase {
    func testPresentersNeedASelectedSet() throws {
        let app = try makeModel()
        app.presentTags()
        XCTAssertNil(app.sheet)
        app.selectedSetPath = "/tmp/a.als"
        app.presentTags()
        XCTAssertEqual(app.sheet, .tags(path: "/tmp/a.als"))
    }

    func testFiltersFollowTab() throws {
        let app = try makeModel()
        app.tab = .sets
        app.presentFilters()
        XCTAssertEqual(app.sheet, .filters)
        app.tab = .plugins
        app.presentFilters()
        XCTAssertEqual(app.sheet, .pluginFilters)
        app.sheet = nil
        app.tab = .home
        app.presentFilters()
        XCTAssertNil(app.sheet)
    }

    func testScanFoldersFollowsTab() throws {
        let app = try makeModel()
        app.presentScanFolders()
        XCTAssertEqual(app.sheet, .roots(.projects))
        app.tab = .samples
        app.presentScanFolders()
        XCTAssertEqual(app.sheet, .roots(.samples))
    }

    func testSheetIdsAreDistinct() throws {
        let sheets: [AppSheet] = [.filters, .pluginFilters, .tags(path: "a"), .tags(path: "b"),
                                  .roots(.projects), .roots(.samples), .preview(path: "a"),
                                  .rescue(path: "a"), .export(path: "a"), .help]
        XCTAssertEqual(Set(sheets.map(\.id)).count, sheets.count)
    }

    func testToastIsQueued() throws {
        let app = try makeModel()
        app.toast("hello")
        XCTAssertEqual(app.toasts.count, 1)
    }

    func testPendingOpenPathsAreConsumedOnce() throws {
        let app = try makeModel()
        app.openPaths(["/a.als", "/b.als"])
        XCTAssertEqual(app.takePendingOpenPaths(), ["/a.als", "/b.als"])
        XCTAssertTrue(app.takePendingOpenPaths().isEmpty)
    }
}
