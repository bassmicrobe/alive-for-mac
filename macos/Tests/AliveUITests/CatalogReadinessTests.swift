import XCTest
@testable import AliveCore
@testable import AliveUI

final class CatalogReadinessTests: XCTestCase {
    func testRetainedMissingRootsOverrideOnlyTheirOwnDescendants() {
        let missing = "/Library/Sets/A Project/A.als"
        let nested = "/Library/Sets/Series/B Project/B.als"
        let sibling = "/Library/Sets-other/C Project/C.als"
        let saved = [missing: SetStatus(), nested: SetStatus(), sibling: SetStatus()]
        var scan = ScanStats()
        scan.retainedPreviousCatalog = true
        scan.missingRoots = ["/library/sets/"]

        let shown = CatalogReadiness.statuses(saved, after: scan)

        XCTAssertEqual(shown[missing]?.readiness, .unreadable)
        XCTAssertEqual(shown[nested]?.readiness, .unreadable)
        XCTAssertEqual(shown[sibling]?.readiness, .ready)
        XCTAssertEqual(saved[missing]?.readiness, .ready, "the retained facts remain unchanged")
    }

    func testSuccessfulScansAndOfflineRootsKeepTheirActualStatus() {
        let path = "/Volumes/Offline/Sets/A.als"
        let offline = SetStatus(offlineFiles: 2, offlineVolumes: ["Offline"])
        var scan = ScanStats()
        scan.failedRoots = ["/Volumes/Offline/Sets"]
        scan.retainedPreviousCatalog = true
        XCTAssertEqual(CatalogReadiness.statuses([path: offline], after: scan)[path], offline)

        scan.missingRoots = ["/Volumes/Offline/Sets"]
        scan.retainedPreviousCatalog = false
        XCTAssertEqual(CatalogReadiness.statuses([path: SetStatus()], after: scan)[path]?.readiness, .ready)
        XCTAssertEqual(CatalogReadiness.statuses([path: offline], after: nil)[path], offline)
    }
}

@MainActor
final class RetainedCatalogReadinessTests: XCTestCase {
    func testMissingRootChangesHomeAndSetsReadinessUntilASuccessfulRecoveryScan() async throws {
        let scratch = makeHomeScratch()
        let root = scratch.sub("Library")
        let siblingRoot = scratch.sub("Library-other")
        let missingSet = try scratch.writeSet("Library/A Project/A.als")
        let otherSet = try scratch.writeSet("Library-other/B Project/B.als")
        let app = AppModel(dataDir: scratch.sub("data"))
        // A deterministic available inventory: sets with no plug-ins are genuinely ready.
        var installed = InstalledPlugin()
        installed.uid = "vst3:fixture"; installed.name = "Fixture"
        var inventory = PluginInventory()
        inventory.add(installed)
        let frozen = inventory
        app.catalog.index.inventoryLoader = { _ in frozen }
        // Direct xctest runs also use the fake backend, never the user's Spotlight domain.
        app.integration = IntegrationCoordinator(app: app, backend: NullSpotlightBackend())
        app.mutateSettings { $0.roots = [root, siblingRoot] }
        defer {
            app.sets.watcher.stop()
            app.sets.watcher.waitUntilArmed()
        }
        app.catalog.start()
        try await waitForScan(app, after: -1)
        XCTAssertEqual(app.home.readySummary, ReadySummary(ready: 2, total: 2))
        XCTAssertEqual(app.sets.readyCount, 2)
        app.sets.filter.readiness = [.ready]
        XCTAssertEqual(Set(app.sets.rows.map(\.path)), [missingSet, otherSet])

        // The watcher is not needed for this test: reproduce the explicit rescan after a move.
        app.sets.watcher.stop()
        app.sets.watcher.waitUntilArmed()
        let moved = scratch.sub("Moved")
        try FileManager.default.moveItem(atPath: root, toPath: moved)
        let beforeMissing = app.catalog.revision
        app.catalog.rescan()
        try await waitForScan(app, after: beforeMissing)

        XCTAssertTrue(app.catalog.lastScanStats?.retainedPreviousCatalog == true)
        XCTAssertEqual(app.catalog.sets.count, 2, "keep the catalog available for recovery")
        XCTAssertEqual(app.catalog.status(for: missingSet)?.readiness, .unreadable)
        XCTAssertEqual(app.catalog.status(for: otherSet)?.readiness, .ready)
        XCTAssertEqual(app.home.readySummary, ReadySummary(ready: 1, total: 2))
        XCTAssertEqual(app.sets.readyCount, 1)
        XCTAssertEqual(app.sets.rows.map(\.path), [otherSet])

        try FileManager.default.moveItem(atPath: moved, toPath: root)
        let beforeRecovery = app.catalog.revision
        app.catalog.rescan()
        try await waitForScan(app, after: beforeRecovery)

        XCTAssertFalse(app.catalog.lastScanStats?.retainedPreviousCatalog ?? true)
        XCTAssertEqual(app.catalog.status(for: missingSet)?.readiness, .ready)
        XCTAssertEqual(app.home.readySummary, ReadySummary(ready: 2, total: 2))
        XCTAssertEqual(app.sets.readyCount, 2)
        XCTAssertEqual(Set(app.sets.rows.map(\.path)), [missingSet, otherSet])
    }

    private func waitForScan(_ app: AppModel, after revision: Int) async throws {
        for _ in 0..<400 where !(app.catalog.isReady && app.catalog.lastScanStats != nil
                                 && app.catalog.revision > revision) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(app.catalog.isReady)
        XCTAssertNotNil(app.catalog.lastScanStats)
        XCTAssertGreaterThan(app.catalog.revision, revision)
    }
}
