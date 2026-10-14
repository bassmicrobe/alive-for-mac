import XCTest
import CoreSpotlight
import AliveCore
@testable import AliveUI

/// Records what would reach the system index; the real CSSearchableIndex is never used.
private final class FakeSpotlightBackend: SpotlightBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var indexedBatches: [[String]] = []
    private var deletedBatches: [[String]] = []
    private var clears = 0

    var indexed: [[String]] { lock.lock(); defer { lock.unlock() }; return indexedBatches }
    var deleted: [[String]] { lock.lock(); defer { lock.unlock() }; return deletedBatches }
    var clearCount: Int { lock.lock(); defer { lock.unlock() }; return clears }

    func index(_ documents: [SpotlightDocument]) async throws {
        lock.withLock { indexedBatches.append(documents.map(\.id)) }
    }
    func delete(ids: [String]) async throws {
        lock.withLock { deletedBatches.append(ids) }
    }
    func deleteAll() async throws {
        lock.withLock { clears += 1 }
    }
}

private func makeSet(_ path: String, name: String = "Probe", tempo: Double = 140, key: String = "C Major",
                     tracks: Int = 12, creator: String = "Ableton Live 11.3", modified: Double = 1_000,
                     plugins: [String] = ["Serum"], vendors: [String] = ["Xfer"], backup: Bool = false) -> SetEntry {
    var e = SetEntry()
    e.path = path; e.name = name; e.projectName = "Proj"; e.tempo = tempo; e.key = key
    e.tracks = tracks; e.creator = creator; e.plugins = plugins; e.pluginVendors = vendors
    e.modified = Date(timeIntervalSince1970: modified); e.isBackup = backup
    return e
}

private func scratchDir() throws -> String {
    let dir = NSTemporaryDirectory() + "alive-ui-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

@MainActor
final class IntegrationSpotlightDocumentTests: XCTestCase {
    override func tearDown() {
        Localizer.shared.preference = .system
        super.tearDown()
    }

    func testDescriptionAndKeywords() throws {
        Localizer.shared.preference = .en
        let set = makeSet("/p/Proj/a.als")
        XCTAssertEqual(SpotlightDocument.describe(set, lang: .en, locale: Locale(identifier: "en_US")), "140 BPM · C Major · 12 tracks · Live 11.3")
        let doc = try XCTUnwrap(SpotlightDocument.make(for: set, tags: ["drums", "serum"], description: "d"))
        XCTAssertEqual(doc.id, "/p/Proj/a.als")
        XCTAssertEqual(doc.title, "Probe")
        // Case-insensitive de-duplication: the tag "serum" is the plugin "Serum".
        XCTAssertEqual(doc.keywords, ["Serum", "Xfer", "drums", "Proj", "C Major"])
    }

    func testJapaneseDescription() {
        Localizer.shared.preference = .ja
        XCTAssertEqual(SpotlightDocument.describe(makeSet("/a.als"), lang: .ja, locale: Locale(identifier: "ja_JP")), "140 BPM · C Major · 12 トラック · Live 11.3")
    }

    func testUnknownPartsAreLeftOutAndBackupsSkipped() {
        Localizer.shared.preference = .en
        XCTAssertEqual(SpotlightDocument.describe(makeSet("/a.als", tempo: 127.5, key: "", tracks: 0, creator: ""),
                                                  lang: .en, locale: Locale(identifier: "en_US")),
                       "127.5 BPM")
        XCTAssertNil(SpotlightDocument.make(for: makeSet("/Backup/a.als", backup: true), tags: [], description: ""))
    }

    func testSignatureChangesWithTagsAndModified() throws {
        let set = makeSet("/a.als")
        let base = try XCTUnwrap(SpotlightDocument.make(for: set, tags: [], description: "x"))
        let tagged = try XCTUnwrap(SpotlightDocument.make(for: set, tags: ["t"], description: "x"))
        let newer = try XCTUnwrap(SpotlightDocument.make(for: makeSet("/a.als", modified: 2_000), tags: [], description: "x"))
        XCTAssertNotEqual(base.signature, tagged.signature)
        XCTAssertNotEqual(base.signature, newer.signature)
        XCTAssertEqual(base.signature, try XCTUnwrap(SpotlightDocument.make(for: set, tags: [], description: "x")).signature)
    }

    func testLinkParsing() {
        XCTAssertEqual(SpotlightLink.path(activityType: CSSearchableItemActionType,
                                          userInfo: [CSSearchableItemActivityIdentifier: "/p/a.als"]), "/p/a.als")
        XCTAssertNil(SpotlightLink.path(activityType: "other", userInfo: [CSSearchableItemActivityIdentifier: "/p/a.als"]))
        XCTAssertNil(SpotlightLink.path(activityType: CSSearchableItemActionType, userInfo: nil))
    }

    func testChunking() {
        XCTAssertEqual([1, 2, 3, 4, 5].chunked(2), [[1, 2], [3, 4], [5]])
        XCTAssertEqual([Int]().chunked(2), [])
    }

    func testStringsComplete() {
        assertStringTableIsComplete(IntegrationStrings.self)
    }
}

final class IntegrationSpotlightIndexerTests: XCTestCase {
    private func docs(_ sets: [SetEntry]) -> [SpotlightDocument] {
        sets.compactMap { SpotlightDocument.make(for: $0, tags: [], description: "d") }
    }

    func testPlanAddsChangesAndRemoves() {
        let a = docs([makeSet("/a.als")])[0]
        let b = docs([makeSet("/b.als")])[0]
        let plan = SpotlightPlan.make(previous: [a.id: a.signature, "/gone.als": "x"], current: [a, b])
        XCTAssertEqual(plan.upserts.map(\.id), ["/b.als"])
        XCTAssertEqual(plan.deletes, ["/gone.als"])
        XCTAssertTrue(SpotlightPlan.make(previous: [a.id: a.signature], current: [a]).isEmpty)
    }

    func testSyncIsIncrementalAndPersistsAcrossInstances() async throws {
        let dir = try scratchDir()
        let backend = FakeSpotlightBackend()
        let first = SpotlightIndexer(dataDir: dir, backend: backend)
        await first.sync(docs([makeSet("/a.als"), makeSet("/b.als")]))
        XCTAssertEqual(backend.indexed.flatMap { $0 }.sorted(), ["/a.als", "/b.als"])

        // A new launch: the snapshot file says what is already there.
        let second = SpotlightIndexer(dataDir: dir, backend: backend)
        await second.sync(docs([makeSet("/a.als"), makeSet("/b.als", modified: 5_000), makeSet("/c.als")]))
        XCTAssertEqual(backend.indexed.dropFirst().flatMap { $0 }.sorted(), ["/b.als", "/c.als"])
        await second.sync(docs([makeSet("/b.als", modified: 5_000)]))
        XCTAssertEqual(backend.deleted.flatMap { $0 }.sorted(), ["/a.als", "/c.als"])
        XCTAssertEqual(backend.clearCount, 0)
    }

    func testBatchesAreBounded() async throws {
        let backend = FakeSpotlightBackend()
        let indexer = SpotlightIndexer(dataDir: try scratchDir(), backend: backend)
        let sets = (0..<(SpotlightIndexer.batchSize * 2 + 5)).map { makeSet("/s\($0).als") }
        await indexer.sync(docs(sets))
        XCTAssertEqual(backend.indexed.map(\.count), [SpotlightIndexer.batchSize, SpotlightIndexer.batchSize, 5])
    }

    func testDescriptionIgnoresTheCurrentUILanguage() {
        // The explicit language wins, whatever Localizer says (the work runs off the main actor).
        let set = makeSet("/a.als")
        let en = SpotlightDocument.describe(set, lang: .en, locale: Locale(identifier: "en_US"))
        let ja = SpotlightDocument.describe(set, lang: .ja, locale: Locale(identifier: "ja_JP"))
        XCTAssertTrue(en.contains("tracks"))
        XCTAssertTrue(ja.contains("トラック"))
    }

    func testRemoveEverythingDeletesTheDomainEvenWithoutASnapshot() async throws {
        let dir = try scratchDir()
        let backend = FakeSpotlightBackend()
        // No snapshot file (data folder deleted, ALIVE_HOME switched, crash before the save):
        // the domain is still emptied, once.
        let fresh = SpotlightIndexer(dataDir: dir, backend: backend)
        await fresh.removeEverything()
        XCTAssertEqual(backend.clearCount, 1)
        await fresh.removeEverything()
        XCTAssertEqual(backend.clearCount, 1, "once per launch while the toggle stays off")

        // Toggled on and off again: cleared again, and the snapshot goes away.
        await fresh.sync(docs([makeSet("/a.als")]))
        await fresh.removeEverything()
        XCTAssertEqual(backend.clearCount, 2)
        XCTAssertFalse(SpotlightSnapshotFile(dir: dir).exists)
    }
}
