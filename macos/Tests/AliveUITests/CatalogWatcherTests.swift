import XCTest
@testable import AliveUI

@MainActor
final class CatalogWatcherTests: XCTestCase {
    func testTheWatcherIsNotRearmedByUnrelatedSettingsChanges() async throws {
        let app = try makeModel()
        let watcher = app.sets.watcher
        watcher.start()
        XCTAssertEqual(watcher.armCount, 1)
        app.mutateSettings { $0.groupByFolder.toggle() }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(watcher.armCount, 1, "same roots: a pending rescan must survive")
        app.mutateSettings { $0.roots.append(NSTemporaryDirectory()) }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(watcher.armCount, 2)
        watcher.waitUntilArmed()
        watcher.stop()
        watcher.waitUntilArmed()
    }

    func testARescanAskedBeforeTheCacheIsReadWaitsForIt() async throws {
        let app = try makeModel()
        app.catalog.start()
        app.catalog.rescan()
        XCTAssertFalse(app.catalog.isScanning, "no scan may race the cache load")
        for _ in 0..<200 where app.catalog.lastScanStats == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(app.catalog.isLoaded)
        XCTAssertNotNil(app.catalog.lastScanStats, "the early request ran after the load")
        XCTAssertFalse(app.catalog.isScanning)
    }
}
