import XCTest
@testable import AliveCore
@testable import AliveUI

/// `CatalogModel.status(for:)` serves real statuses from the scan, and a volume coming or going
/// is handled without a rescan.
@MainActor
final class CatalogStatusTests: XCTestCase {
    private func library() throws -> (app: AppModel, set: String) {
        let base = NSTemporaryDirectory() + "alive-status-ui-" + UUID().uuidString
        let setPath = base + "/lib/A Project/A.als"
        try FileManager.default.createDirectory(atPath: (setPath as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: base + "/data", withIntermediateDirectories: true)
        let xml = "<?xml version=\"1.0\"?><Ableton Creator=\"Ableton Live 12.0\"><LiveSet><Tracks></Tracks>"
            + "<SampleRef><FileRef><RelativePathType Value=\"0\"/><RelativePath Value=\"\"/>"
            + "<Path Value=\"/Volumes/GhostDriveForTests/kick.wav\"/><Type Value=\"2\"/>"
            + "<LivePackName Value=\"\"/><LivePackId Value=\"\"/><OriginalFileSize Value=\"0\"/></FileRef></SampleRef>"
            + "</LiveSet></Ableton>"
        try Gzip.compress(Data(xml.utf8)).write(to: URL(fileURLWithPath: setPath))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: base) }
        let app = AppModel(dataDir: base + "/data")
        app.mutateSettings { $0.roots = [base + "/lib"] }
        return (app, setPath)
    }

    private func waitForCatalog(_ app: AppModel) async throws {
        app.catalog.start()
        for _ in 0..<400 where !(app.catalog.isReady && app.catalog.lastScanStats != nil) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(app.catalog.isReady)
    }

    func testStatusComesFromTheScanAndIsServedByPath() async throws {
        let (app, path) = try library()
        try await waitForCatalog(app)
        let status = try XCTUnwrap(app.catalog.status(for: path))
        XCTAssertEqual(status.offlineFiles, 1)
        XCTAssertEqual(status.offlineVolumes, ["GhostDriveForTests"])
        XCTAssertEqual(status.missingFiles, 0)
        XCTAssertNil(app.catalog.status(for: "/no/such/set.als"))
        XCTAssertEqual(app.catalog.offlineReferences[path], ["/Volumes/GhostDriveForTests/kick.wav"])
    }

    func testStatusIsAvailableFromTheCacheAtTheNextLaunch() async throws {
        let (app, path) = try library()
        try await waitForCatalog(app)
        let second = AppModel(dataDir: app.dataDir)
        second.mutateSettings { $0.roots = app.settings.roots }
        second.catalog.start()
        for _ in 0..<200 where !second.catalog.isLoaded { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(second.catalog.status(for: path)?.offlineFiles, 1)
        // Let its scan finish before the model goes away.
        for _ in 0..<400 where !(second.catalog.isReady && second.catalog.lastScanStats != nil) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func testAMountNotificationWithNothingNewChangesNothing() async throws {
        let (app, path) = try library()
        try await waitForCatalog(app)
        let revision = app.catalog.revision
        app.catalog.volumesChanged()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(app.catalog.revision, revision)
        XCTAssertEqual(app.catalog.status(for: path)?.offlineFiles, 1)
    }
}
