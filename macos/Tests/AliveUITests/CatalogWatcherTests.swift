import XCTest
import AliveCore
@testable import AliveUI

@MainActor
final class CatalogWatcherTests: XCTestCase {
    func testStartingTheCatalogArmsTheWatcherAndResavedSetsRefreshAutomatically() async throws {
        let scratch = makeHomeScratch()
        let path = try scratch.writeSet("lib/Watched Project/A.als")
        let app = AppModel(dataDir: scratch.sub("data"))
        app.mutateSettings {
            $0.roots = [scratch.sub("lib")]
            $0.spotlight = false
        }
        let watcher = app.sets.watcher
        defer {
            watcher.stop()
            watcher.waitUntilArmed()
        }

        // Exercise the production lifecycle, rather than starting the watcher in the test.
        app.catalog.start()
        app.catalog.start()
        watcher.waitUntilArmed()
        XCTAssertEqual(watcher.armCount, 1, "catalog startup must arm the watch exactly once")
        for _ in 0..<400 where !(app.catalog.isReady && app.catalog.lastScanStats != nil) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(app.catalog.isReady)
        let initial = try XCTUnwrap(app.catalog.sets.first { $0.path == path })
        XCTAssertEqual(initial.shortVersion, "12.3.5")

        let xml = HomeFixtures.setXML(withClip: true)
            .replacingOccurrences(of: "12.3.5", with: "12.3.6")
        try Gzip.compress(Data(xml.utf8)).write(to: URL(fileURLWithPath: path), options: .atomic)
        // Keep cache invalidation independent of the file system's timestamp resolution.
        try FileManager.default.setAttributes([.modificationDate: initial.modified.addingTimeInterval(5)],
                                             ofItemAtPath: path)
        for _ in 0..<400 where app.catalog.sets.first(where: { $0.path == path })?.shortVersion != "12.3.6" {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(app.catalog.sets.first { $0.path == path }?.shortVersion, "12.3.6",
                       "saving an .als must refresh the catalog without a manual rescan")
        XCTAssertEqual(watcher.armCount, 1, "a file change must not replace the watch")
    }

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
