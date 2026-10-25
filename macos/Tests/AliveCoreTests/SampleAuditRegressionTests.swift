// Mac-only: regression fixtures for the October 25 sample performance/state audit.
import XCTest
@testable import AliveCore

final class SampleAuditRegressionTests: XCTestCase {
    private func library(files: Int, sparsePrints: Bool = false) -> SampleIndex {
        var index = SampleIndex()
        var root = SampleFolder()
        root.path = "/library"; root.name = root.path
        root.files = Array(0..<files); root.totalSamples = files
        index.roots = [0]; index.folders = [root]
        index.files = (0..<files).map { i in
            var file = SampleFile()
            file.name = "sound.wav"; file.size = 100
            file.print = sparsePrints && i % 2 == 1 ? 7 : 0
            return file
        }
        return index
    }

    func testSameSizeAiffReplacementRechecksPreviewSupport() throws {
        let t = makeTemp("aiff-replacement")
        let root = t.mkdir("Library"), path = root + "/sound.aif"
        let unsupported = SampleFixtures.aiff(compression: "able")
        let supported = SampleFixtures.aiff(compression: "sowt")
        XCTAssertEqual(unsupported.count, supported.count)

        try unsupported.write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: path)
        let original = SampleIndex.build(roots: [root], disabled: [])
        XCTAssertFalse(try XCTUnwrap(original.files.first).canPreview)
        let cached = try SampleCache.decode(SampleCache.encode(original))

        try supported.write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: path)
        let changed = SampleIndex.build(roots: [root], disabled: [], previous: cached)
        XCTAssertTrue(try XCTUnwrap(changed.files.first).canPreview)

        try unsupported.write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 3_000)], ofItemAtPath: path)
        let changedAgain = SampleIndex.build(roots: [root], disabled: [], previous: changed)
        XCTAssertFalse(try XCTUnwrap(changedAgain.files.first).canPreview)
    }

    func testLegacyAiffCacheWithoutDatesStillKeepsItsPreviewFlag() {
        let t = makeTemp("aiff-legacy-cache")
        let root = t.mkdir("Library")
        SampleFixtures.put(SampleFixtures.aiff(), at: root + "/sound.aif")
        var legacy = SampleIndex.build(roots: [root], disabled: [])
        legacy.files[0].modified = nil
        legacy.files[0].silent = true
        let changed = SampleIndex.build(roots: [root], disabled: [], previous: legacy)
        XCTAssertTrue(changed.files[0].silent, "v2 cached flags do not force every AIFF to be opened again")
        XCTAssertNotNil(changed.files[0].modified)
    }

    func testCopiesCanCancelWhenPollingPositionsHaveNoFingerprint() {
        let index = library(files: 8_192, sparsePrints: true)
        var polls = 0
        let cancelled = SampleCopies.find(in: index, isCancelled: {
            polls += 1
            return polls >= 2
        })
        XCTAssertEqual(polls, 2)
        XCTAssertTrue(cancelled.files.isEmpty)
        XCTAssertEqual(SampleCopies.find(in: index).files.count, 4_096)
    }

    func testCancelledTreeListingDoesNotPublishRootRows() {
        let result = SampleLister.listing(index: library(files: 1), usage: .empty, copies: .empty,
                                          lens: .all, sort: SampleSort(), open: [], query: "",
                                          isCancelled: { true })
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.matches, 0)
    }

    func testTreeListingCanCancelInsideOneWideOpenFolder() {
        let index = library(files: 8_192)
        var polls = 0
        let result = SampleLister.listing(index: index, usage: .empty, copies: .empty,
                                          lens: .all, sort: SampleSort(), open: ["/library"], query: "",
                                          isCancelled: {
                                              polls += 1
                                              return polls >= 5
                                          })
        XCTAssertGreaterThanOrEqual(polls, 5)
        XCTAssertTrue(result.rows.isEmpty, "a cancelled tree must not return its partial rows")
        XCTAssertEqual(result.matches, 0)
        let complete = SampleLister.listing(index: index, usage: .empty, copies: .empty,
                                             lens: .all, sort: SampleSort(), open: ["/library"], query: "")
        XCTAssertEqual(complete.rows.count, 8_193)
        XCTAssertEqual(complete.rows.first?.kind, .folder(0))
        XCTAssertEqual(complete.rows.last?.depth, 1)
    }
}
