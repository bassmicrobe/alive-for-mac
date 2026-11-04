import XCTest
@testable import AliveCore
@testable import AliveUI

/// 9ce4b4b: a folder added while a scan runs does not break it, and its scan runs right after.
@MainActor
final class CatalogScanQueueUpstream133Tests: XCTestCase {
    func testFolderAddedDuringAScanIsScannedRightAfterIt() async throws {
        let scratch = makeHomeScratch()
        let first = try scratch.writeSet("one/Project/A.als")
        let second = try scratch.writeSet("two/Project/B.als")
        var settings = Settings()
        settings.roots = [scratch.sub("one")]
        settings.spotlight = false
        settings.finderTags = false
        settings.checkUpdates = false
        try settings.save(dir: scratch.sub("data"))
        let app = AppModel(dataDir: scratch.sub("data"))
        let catalog = app.catalog
        let gate = ScanGate()
        defer { gate.resume() }
        catalog.index.inventoryLoader = { _ in gate.pause(); return PluginInventory() }

        catalog.start()
        try await waitUntil { gate.hasEntered }
        app.sets.watcher.stop()
        app.sets.watcher.waitUntilArmed()
        let revision = catalog.revision
        XCTAssertTrue(catalog.addRoot(scratch.sub("two")))
        XCTAssertTrue(catalog.isScanning, "the running scan is not replaced")

        gate.resume()
        try await waitUntil { catalog.isReady && Set(catalog.sets.map(\.path)) == [first, second] }
        XCTAssertGreaterThanOrEqual(catalog.revision, revision + 2,
                                    "the first scan finished and published, then the follow-up did")
        XCTAssertEqual(catalog.lastScanStats?.cancelled, false)
        XCTAssertFalse(gate.timedOut)
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("background operation did not reach the expected state", file: file, line: line)
        throw CancellationError()
    }
}

/// Holds the first scan at the end of its run (inside the plugin inventory load) until `resume`.
private final class ScanGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var entries = 0
    private var timeout = false

    var hasEntered: Bool { lock.lock(); defer { lock.unlock() }; return entries > 0 }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return timeout }

    func pause() {
        lock.lock()
        entries += 1
        let first = entries == 1
        lock.unlock()
        guard first else { return }       // the follow-up scan runs straight through
        let result = semaphore.wait(timeout: .now() + 10)
        lock.lock(); timeout = result == .timedOut; lock.unlock()
    }

    func resume() { semaphore.signal() }
}
