import XCTest
@testable import AliveUI

@MainActor
final class AppModelTests: XCTestCase {
    func testPresentersNeedASelectedSet() {
        let app = AppModel()
        app.presentTags()
        XCTAssertNil(app.sheet)
        app.selectedSetPath = "/tmp/a.als"
        app.presentTags()
        XCTAssertEqual(app.sheet, .tags(path: "/tmp/a.als"))
    }

    func testFiltersFollowTab() {
        let app = AppModel()
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

    func testScanFoldersFollowsTab() {
        let app = AppModel()
        app.presentScanFolders()
        XCTAssertEqual(app.sheet, .roots(.projects))
        app.tab = .samples
        app.presentScanFolders()
        XCTAssertEqual(app.sheet, .roots(.samples))
    }

    func testSheetIdsAreDistinct() {
        let sheets: [AppSheet] = [.filters, .pluginFilters, .tags(path: "a"), .tags(path: "b"),
                                  .roots(.projects), .roots(.samples), .preview(path: "a"),
                                  .rescue(path: "a"), .export(path: "a"), .help]
        XCTAssertEqual(Set(sheets.map(\.id)).count, sheets.count)
    }

    func testToastIsQueued() {
        let app = AppModel()
        app.toast("hello")
        XCTAssertEqual(app.toasts.count, 1)
    }

    func testPendingOpenPathsAreConsumedOnce() {
        let app = AppModel()
        app.openPaths(["/a.als", "/b.als"])
        XCTAssertEqual(app.takePendingOpenPaths(), ["/a.als", "/b.als"])
        XCTAssertTrue(app.takePendingOpenPaths().isEmpty)
    }
}
