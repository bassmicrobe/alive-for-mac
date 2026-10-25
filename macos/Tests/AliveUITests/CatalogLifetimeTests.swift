import XCTest
@testable import AliveCore
@testable import AliveUI

/// A background operation must retain the owner of CatalogModel's unowned references only
/// until its last publication, even if the window/test releases its AppModel while it waits.
@MainActor
final class CatalogLifetimeTests: XCTestCase {
    func testCacheStartupRetainsItsOwnerThroughInventoryPublication() async throws {
        let scratch = makeHomeScratch()
        var app: AppModel? = try makeApp(in: scratch)
        let catalog = try XCTUnwrap(app?.catalog)
        let owner = CatalogWeakOwner(app)
        let gate = CatalogLifetimeGate()
        defer { gate.resume() }
        catalog.index.inventoryLoader = { _ in gate.pause(); return PluginInventory() }

        catalog.start()
        try await waitUntil { gate.hasEntered }
        stopWatcher(app)
        let revision = catalog.revision
        app = nil
        XCTAssertNotNil(owner.app, "startup must keep its unowned owner alive while inventory waits")

        gate.resume()
        try await waitUntil { catalog.revision > revision }
        try await waitUntil { owner.app == nil }
        XCTAssertTrue(catalog.isReady)
        XCTAssertFalse(gate.timedOut)
    }

    func testScanRetainsItsOwnerThroughCompletionAndThenReleasesIt() async throws {
        let scratch = makeHomeScratch()
        let path = try scratch.writeSet("lib/Project/A.als")
        var app: AppModel? = try makeApp(in: scratch, roots: [scratch.sub("lib")])
        let catalog = try XCTUnwrap(app?.catalog)
        let owner = CatalogWeakOwner(app)
        let gate = CatalogLifetimeGate()
        defer { gate.resume() }
        catalog.index.inventoryLoader = { _ in gate.pause(); return PluginInventory() }

        catalog.start()
        try await waitUntil { gate.hasEntered }
        stopWatcher(app)
        XCTAssertTrue(catalog.isScanning)
        app = nil
        XCTAssertNotNil(owner.app, "a scan must keep its unowned owner alive across scanAsync")

        gate.resume()
        try await waitUntil { catalog.isReady && catalog.lastScanStats != nil }
        try await waitUntil { owner.app == nil }
        XCTAssertEqual(catalog.sets.map(\.path), [path])
        XCTAssertFalse(gate.timedOut)
    }

    func testSupersededScanReleasesItsOwnerAfterTheReplacementFinishes() async throws {
        let scratch = makeHomeScratch()
        try scratch.writeSet("lib/Project/A.als")
        var app: AppModel? = try makeApp(in: scratch, roots: [scratch.sub("lib")])
        let catalog = try XCTUnwrap(app?.catalog)
        let owner = CatalogWeakOwner(app)
        let gate = CatalogLifetimeGate()
        defer { gate.resume() }
        catalog.index.inventoryLoader = { _ in gate.pause(); return PluginInventory() }

        catalog.start()
        try await waitUntil { gate.hasEntered }
        stopWatcher(app)
        catalog.rescan(full: false)      // cancels the first task and waits for it to stop
        app = nil
        XCTAssertNotNil(owner.app)

        gate.resume()
        try await waitUntil { catalog.isReady && catalog.lastScanStats != nil }
        try await waitUntil { owner.app == nil }
        XCTAssertEqual(gate.entryCount, 2, "both the cancelled scan and its replacement finished")
        XCTAssertEqual(catalog.lastScanStats?.cancelled, false)
        XCTAssertFalse(gate.timedOut)
    }

    func testVolumeRecheckRetainsItsOwnerThroughTheSecondAwait() async throws {
        let scratch = makeHomeScratch()
        let volume = "AliveLifetime-" + UUID().uuidString
        let reference = "<SampleRef><FileRef><RelativePathType Value=\"0\"/><RelativePath Value=\"\"/>"
            + "<Path Value=\"/Volumes/\(volume)/kick.wav\"/><Type Value=\"2\"/>"
            + "<LivePackName Value=\"\"/><LivePackId Value=\"\"/><OriginalFileSize Value=\"0\"/>"
            + "</FileRef></SampleRef>"
        let path = try scratch.writeSet("lib/Project/A.als")
        let xml = HomeFixtures.setXML(withClip: true)
            .replacingOccurrences(of: "</LiveSet>", with: reference + "</LiveSet>")
        try Gzip.compress(Data(xml.utf8)).write(to: URL(fileURLWithPath: path))
        var app: AppModel? = try makeApp(in: scratch, roots: [scratch.sub("lib")])
        let catalog = try XCTUnwrap(app?.catalog)
        let index = catalog.index
        let owner = CatalogWeakOwner(app)
        index.inventoryLoader = { _ in PluginInventory() }
        index.mountProvider = { [] }
        catalog.start()
        try await waitUntil { catalog.isReady && catalog.lastScanStats != nil }
        stopWatcher(app)
        XCTAssertEqual(catalog.status(for: path)?.offlineFiles, 1)

        let gate = CatalogLifetimeGate()
        defer { gate.resume() }
        index.mountProvider = { [volume] }
        // volumesDidChange publishes first; pause the following recheck's status publication.
        // Both hooks run sequentially on this one volume task, with no scan running.
        index.beforeStatusPublish = { index.beforeStatusPublish = { gate.pause() } }
        let revision = catalog.revision
        catalog.volumesChanged()
        try await waitUntil { gate.hasEntered }
        app = nil
        XCTAssertNotNil(owner.app, "the owner must survive the recheck await after mount discovery")

        gate.resume()
        try await waitUntil { catalog.revision > revision }
        try await waitUntil { owner.app == nil }
        XCTAssertEqual(catalog.status(for: path)?.offlineFiles, 0)
        XCTAssertEqual(catalog.status(for: path)?.missingFiles, 1)
        XCTAssertFalse(gate.timedOut)
    }

    private func makeApp(in scratch: HomeScratch, roots: [String] = []) throws -> AppModel {
        var settings = Settings()
        settings.roots = roots
        settings.spotlight = false
        settings.finderTags = false
        settings.checkUpdates = false
        try settings.save(dir: scratch.sub("data"))
        return AppModel(dataDir: scratch.sub("data"))
    }

    private func stopWatcher(_ app: AppModel?) {
        app?.sets.watcher.stop()
        app?.sets.watcher.waitUntilArmed()
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("background operation did not reach the expected state", file: file, line: line)
        throw WaitError.timedOut
    }

    private enum WaitError: Error { case timedOut }
}

@MainActor
private final class CatalogWeakOwner {
    weak var app: AppModel?
    init(_ app: AppModel?) { self.app = app }
}

private final class CatalogLifetimeGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var entries = 0
    private var timeout = false

    var hasEntered: Bool { entryCount > 0 }
    var entryCount: Int { lock.lock(); defer { lock.unlock() }; return entries }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return timeout }

    func pause() {
        lock.lock()
        entries += 1
        let first = entries == 1
        lock.unlock()
        guard first else { return }     // a replacement scan is allowed to finish immediately
        let result = semaphore.wait(timeout: .now() + 10)
        lock.lock(); timeout = result == .timedOut; lock.unlock()
    }

    func resume() { semaphore.signal() }
}
