import XCTest
@testable import AliveCore
@testable import AliveUI

/// The Samples list is derived off the main actor and published as one snapshot. Silent files only.
@MainActor
final class SamplesSnapshotTests: XCTestCase {
    private var root = ""

    private func wav(_ frames: Int, seed: UInt8 = 0) -> Data {
        func le(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        let bytes = frames * 2
        var d = Array("RIFF".utf8) + le(36 + bytes, 4) + Array("WAVE".utf8) + Array("fmt ".utf8) + le(16, 4)
        d += le(1, 2) + le(1, 2) + le(44100, 4) + le(88200, 4) + le(2, 2) + le(16, 2)
        d += Array("data".utf8) + le(bytes, 4) + [UInt8](repeating: seed, count: bytes)
        return Data(d)
    }

    private func put(_ data: Data, _ rel: String) {
        let p = root + "/" + rel
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try! data.write(to: URL(fileURLWithPath: p))
    }

    private func makeApp() throws -> AppModel {
        let base = NSTemporaryDirectory() + "alive-samples-snap-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: base + "/data", withIntermediateDirectories: true)
        root = base + "/Lib"
        put(wav(4410), "Drums/kick.wav")
        put(wav(4410), "Pads/kick.wav")
        put(wav(8820, seed: 1), "Pads/warm.wav")
        addTeardownBlock { try? FileManager.default.removeItem(atPath: base) }
        let app = AppModel(dataDir: base + "/data")
        app.audio.volume = 0
        app.mutateSettings { $0.sampleRoots = [self.root] }
        return app
    }

    private func started(_ app: AppModel) async -> SamplesModel {
        let m = app.samples
        m.start()
        await m.loadTask?.value
        await m.scanTask?.value
        await m.settle()
        return m
    }

    func testTheGettersNeverComputeAndTheSnapshotArrivesOnce() async throws {
        let app = try makeApp()
        let m = app.samples
        m.start()
        await m.loadTask?.value
        await m.scanTask?.value
        XCTAssertTrue(m.isPreparing, "the index is new: its rows are still being built")
        XCTAssertTrue(m.listing.rows.isEmpty, "and a getter returns nothing rather than working them out")
        XCTAssertTrue(m.usageUnknown)
        await m.settle()
        XCTAssertFalse(m.isPreparing)
        XCTAssertEqual(m.snapshot?.key.indexGeneration, m.indexGeneration)
        XCTAssertEqual(m.listing.rows.count, 1)
    }

    func testDuplicatesAreFoundOnlyWhenSomethingAsksForThem() async throws {
        let app = try makeApp()
        let m = await started(app)
        XCTAssertNil(m.snapshot?.copies, "the tree with the default columns needs no copies")
        XCTAssertEqual(m.copies.files.count, 0)

        m.lens = .duplicates
        await m.settle()
        XCTAssertEqual(m.snapshot?.copies?.files.count, 2, "the Duplicates lens does")
        XCTAssertEqual(m.shownCount, 2)

        m.lens = .all
        await m.settle()
        XCTAssertNotNil(m.snapshot?.copies, "found already for this index: kept, not dropped and found again")

        // A panel asks for them by itself.
        let other = try makeApp()
        let n = await started(other)
        XCTAssertNil(n.snapshot?.copies)
        XCTAssertEqual(n.copiesForPanel.files.count, 0, "not there yet …")
        await n.settle()
        XCTAssertEqual(n.copiesForPanel.files.count, 2, "… and there once it is built")
    }

    func testTheNewestRequestWinsAndAnOldBuildIsNotPublished() async throws {
        let app = try makeApp()
        let m = await started(app)
        m.lens = .duplicates
        _ = m.listing                                            // starts a build for Duplicates
        m.lens = .neverUsed
        _ = m.listing                                            // and another one that replaces it
        m.lens = .mostUsed
        await m.settle()
        XCTAssertEqual(m.snapshot?.key.lens, .mostUsed)
        XCTAssertFalse(m.isPreparing)
    }

    func testASearchKeepsTheRowsOfTheSameLibraryUntilTheNewOnesArrive() async throws {
        let app = try makeApp()
        let m = await started(app)
        m.toggleFolder(SampleIndex.norm(root))
        await m.settle()
        let before = m.listing.rows.count
        XCTAssertGreaterThan(before, 1)
        app.searchText = "warm"
        XCTAssertTrue(m.isPreparing)
        XCTAssertEqual(m.listing.rows.count, before, "no flash of an empty list")
        await m.settle()
        XCTAssertEqual(m.listing.rows.count, 1)
        app.searchText = ""
    }

    func testAScrollWaitsForTheRowsItPointsAt() async throws {
        let app = try makeApp()
        let m = await started(app)
        let path = SampleIndex.norm(root + "/Pads/warm.wav")
        m.showInTree(path)
        XCTAssertNil(m.scrollTarget, "the rows around it are not built yet")
        await m.settle()
        XCTAssertEqual(m.scrollTarget?.id, path)
        XCTAssertNotNil(m.listing.rows.first { $0.id == path })
    }

    func testTheBuilderReusesWhatDidNotChange() throws {
        _ = try makeApp()
        let index2 = SampleIndex.build(roots: [root], disabled: [], previous: nil, progress: { _ in }, isCancelled: { false })
        let key = SamplesSnapshotKey(indexGeneration: 1, catalogRevision: 1, lens: .duplicates, sort: SampleSort(),
                                     openRevision: 0, query: "", wantsCopies: true)
        let first = try XCTUnwrap(SamplesSnapshotBuilder.build(
            SamplesSnapshotInput(key: key, index: index2, sets: [], open: [], previous: nil), isCancelled: { false }))
        XCTAssertEqual(first.copies?.files.count, 2)

        var narrowed = key
        narrowed.query = "warm"
        let second = try XCTUnwrap(SamplesSnapshotBuilder.build(
            SamplesSnapshotInput(key: narrowed, index: index2, sets: [], open: [], previous: first), isCancelled: { false }))
        XCTAssertEqual(second.copies?.files.count, 2, "copies carried over from the same index")
        XCTAssertEqual(second.listing.rows.count, 0, "the search is applied to the lens")

        var polled = 0
        XCTAssertNil(SamplesSnapshotBuilder.build(
            SamplesSnapshotInput(key: key, index: index2, sets: [], open: [], previous: nil),
            isCancelled: { polled += 1; return true }), "a cancelled build publishes nothing")
        XCTAssertEqual(polled, 1, "and stops at the first check")
    }
}
