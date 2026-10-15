import XCTest
import AliveCore
@testable import AliveUI

@MainActor
final class WidgetPublicationTests: XCTestCase {
    func testSupersededSlowSnapshotCannotOverwriteTheLatestCatalog() async throws {
        let dir = NSTemporaryDirectory() + "alive-widget-order-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let publisher = WidgetSnapshotPublisher(reload: {})
        let started = expectation(description: "old snapshot is being built")
        let resume = DispatchSemaphore(value: 0)
        let old = WidgetSnapshot.make(activity: .empty, sets: [], now: Date(timeIntervalSince1970: 10))
        var newer = old
        newer.activeDays = 99
        let latest = newer
        let first = publisher.publish(dir: dir) {
            started.fulfill()
            _ = resume.wait(timeout: .now() + 10)
            return old
        }
        await fulfillment(of: [started], timeout: 5)
        let second = publisher.publish(dir: dir) { latest }
        resume.signal()
        await second.value
        await first.value
        XCTAssertEqual(WidgetSnapshot.load(from: WidgetSnapshot.appFileURL(dataDir: dir))?.activeDays, 99)
    }
}

private actor PausingSpotlightBackend: SpotlightBackend {
    let firstBatch: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var indexed: [String] = []
    init(firstBatch: XCTestExpectation) { self.firstBatch = firstBatch }

    func index(_ documents: [SpotlightDocument]) async throws {
        let first = indexed.isEmpty
        indexed.append(contentsOf: documents.map(\.id))
        if first {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                firstBatch.fulfill()
            }
        }
    }
    func resume() { continuation?.resume(); continuation = nil }
    func delete(ids: [String]) async throws {}
    func deleteAll() async throws {}
}

final class SpotlightCancellationTests: XCTestCase {
    func testCancellationStopsAfterTheCurrentBatchAndPreservesItsCheckpoint() async throws {
        let dir = NSTemporaryDirectory() + "alive-spotlight-cancel-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let entered = expectation(description: "first backend batch started")
        let backend = PausingSpotlightBackend(firstBatch: entered)
        let indexer = SpotlightIndexer(dataDir: dir, backend: backend)
        let documents = (0..<450).map { i in
            SpotlightDocument(id: "/set-\(i).als", title: "Set \(i)", displayName: "Set \(i)",
                              contentDescription: "", keywords: [], modified: .distantPast, created: .distantPast)
        }
        let task = Task { await indexer.sync(documents) }
        await fulfillment(of: [entered], timeout: 5)
        task.cancel()
        await backend.resume()
        await task.value
        let firstIDs = await backend.indexed
        XCTAssertEqual(firstIDs.count, SpotlightIndexer.batchSize)
        XCTAssertEqual(SpotlightSnapshotFile(dir: dir).load().count, SpotlightIndexer.batchSize)
        await indexer.sync(documents)
        let allIDs = await backend.indexed
        XCTAssertEqual(allIDs.count, 450, "The completed batch must not be sent again")
        XCTAssertEqual(SpotlightSnapshotFile(dir: dir).load().count, 450)
    }
}
