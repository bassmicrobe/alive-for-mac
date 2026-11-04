import XCTest
@testable import AliveCore
@testable import AliveUI

/// Upstream a6c8dc1 / 9ce4b4b: Stat shows the main window's catalog and grows with the interface scale.
@MainActor
final class StatCatalogUpstream133Tests: XCTestCase {
    private func waitForScan(_ app: AppModel, after revision: Int) async throws {
        for _ in 0..<400 where !(app.catalog.isReady && app.catalog.lastScanStats != nil
                                 && app.catalog.revision > revision) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(app.catalog.isReady)
        XCTAssertGreaterThan(app.catalog.revision, revision)
    }

    func testTheCloudShowsTheMainWindowsCatalogAndFollowsItsRescans() async throws {
        let scratch = makeHomeScratch()
        let root = scratch.sub("Sets")
        try scratch.writeSet("Sets/A Project/A.als")
        try scratch.writeSet("Sets/B Project/B.als")
        let app = AppModel(dataDir: scratch.sub("data"))
        app.catalog.index.inventoryLoader = { _ in PluginInventory() }
        app.integration = IntegrationCoordinator(app: app, backend: NullSpotlightBackend())
        app.mutateSettings { $0.roots = [root] }
        defer {
            app.sets.watcher.stop()
            app.sets.watcher.waitUntilArmed()
        }
        app.catalog.start()
        try await waitForScan(app, after: -1)

        // Stat has no index of its own: it takes in whatever the catalog holds.
        app.stat.syncCatalog()
        XCTAssertEqual(app.stat.visibleCount, 2)
        XCTAssertEqual(app.stat.scene.nodes.count, 2)

        // A rescan the main window runs shows in the cloud at the next revision.
        app.sets.watcher.stop()
        app.sets.watcher.waitUntilArmed()
        try scratch.writeSet("Sets/C Project/C.als")
        let before = app.catalog.revision
        app.catalog.rescan()
        try await waitForScan(app, after: before)
        app.stat.syncCatalog()
        XCTAssertEqual(app.stat.visibleCount, 3)
        XCTAssertEqual(app.stat.scene.nodes.count, 3)
    }

    func testTheWindowGrowsWithTheInterfaceScaleButNotPastTheScreen() {
        XCTAssertEqual(StatWindowSize.make(uiScale: 100).ideal, CGSize(width: 1320, height: 820))
        let big = StatWindowSize.make(uiScale: 125)
        XCTAssertEqual(big.ideal, CGSize(width: 1650, height: 1025))
        XCTAssertEqual(big.minimum, CGSize(width: 1300, height: 800))
        XCTAssertEqual(StatWindowSize.make(uiScale: 75).minimum, CGSize(width: 780, height: 480))

        let small = StatWindowSize.make(uiScale: 125, screen: CGSize(width: 1366, height: 720))
        XCTAssertEqual(small.ideal, CGSize(width: 1366, height: 720))
        XCTAssertEqual(small.minimum, CGSize(width: 1300, height: 720))
    }

    func testTheStatusLineSaysOneProjectInTheSingular() {
        XCTAssertEqual(StatStrings.projects(1), StatStrings.projectsCountOne.s)
        XCTAssertEqual(StatStrings.projects(12), StatStrings.projectsCount.f(12))
    }
}
