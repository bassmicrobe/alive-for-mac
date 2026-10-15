import XCTest
import AliveCore
@testable import AliveUI

final class IntegrationFinderTagMergeTests: XCTestCase {
    func testKeepsPersonalTagsAndAddsOurs() {
        let r = FinderTagSync.merge(current: ["Red\n6", "mine"], desired: ["drums"], recorded: [])
        XCTAssertEqual(r.tags, ["Red\n6", "mine", "drums"])
        XCTAssertEqual(r.owned, ["drums"])
    }

    func testRemovesOnlyTagsAliveAdded() {
        let r = FinderTagSync.merge(current: ["mine", "old", "keep"], desired: ["keep"], recorded: ["old", "keep"])
        XCTAssertEqual(r.tags, ["mine", "keep"])
        XCTAssertEqual(r.owned, ["keep"])
    }

    func testTagThePersonAlreadyHadStaysTheirs() {
        let r = FinderTagSync.merge(current: ["Drums"], desired: ["drums"], recorded: [])
        XCTAssertEqual(r.tags, ["Drums"])
        XCTAssertEqual(r.owned, [])
        // Dropped from the project later: still the person's, so it stays.
        let later = FinderTagSync.merge(current: r.tags, desired: [], recorded: r.owned)
        XCTAssertEqual(later.tags, ["Drums"])
    }

    func testColouredTagMatchesByName() {
        let r = FinderTagSync.merge(current: ["Drums\n2"], desired: ["drums"], recorded: ["drums"])
        XCTAssertEqual(r.tags, ["Drums\n2"])
        XCTAssertEqual(r.owned, ["drums"])
    }
}

final class IntegrationFinderTagDiskTests: XCTestCase {
    private func scratch() throws -> String {
        let dir = NSTemporaryDirectory() + "alive-ui-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func tags(of dir: String) throws -> [String] {
        try URL(fileURLWithPath: dir).resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
    }

    func testWritesMergesAndRemovesOnATempFolder() throws {
        let data = try scratch()
        let project = try scratch()
        try (URL(fileURLWithPath: project) as NSURL).setResourceValue(["mine"], forKey: .tagNamesKey)
        let sync = FinderTagSync(dataDir: data)

        XCTAssertEqual(sync.sync(desired: [project: ["drums", "wip"]]), 1)
        XCTAssertEqual(Set(try tags(of: project)), ["mine", "drums", "wip"])

        // Unchanged desire: nothing to write.
        XCTAssertEqual(sync.sync(desired: [project: ["drums", "wip"]]), 0)

        // A new instance (new launch) still knows what it added.
        XCTAssertEqual(FinderTagSync(dataDir: data).sync(desired: [project: ["drums"]]), 1)
        XCTAssertEqual(Set(try tags(of: project)), ["mine", "drums"])

        // The project loses all tags: Alive's go, the person's stay.
        XCTAssertEqual(FinderTagSync(dataDir: data).sync(desired: [project: []]), 1)
        XCTAssertEqual(try tags(of: project), ["mine"])
        XCTAssertTrue(FinderTagSync(dataDir: data).loadRecord().isEmpty)
    }

    func testMissingFolderIsNotCreatedAndDoesNotWriteAnEmptyRecord() throws {
        let data = try scratch()
        let gone = NSTemporaryDirectory() + "alive-ui-tests-missing-" + UUID().uuidString
        XCTAssertEqual(FinderTagSync(dataDir: data).sync(desired: [gone: ["x"]]), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gone))
        XCTAssertFalse(FileManager.default.fileExists(atPath: data + "/findertags.cfg"))
    }

    func testOfflineFolderKeepsOwnershipAndRemovesOnlyAliveTagsAfterReconnecting() throws {
        let data = try scratch()
        let volume = try scratch()
        let project = volume + "/project"
        let offline = volume + "/offline"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        try (URL(fileURLWithPath: project) as NSURL).setResourceValue(["mine"], forKey: .tagNamesKey)
        let sync = FinderTagSync(dataDir: data)
        XCTAssertEqual(sync.sync(desired: [project: ["drums"]]), 1)
        let saved = try Data(contentsOf: URL(fileURLWithPath: data + "/findertags.cfg"))

        // A disconnected volume disappears from the catalog. A rename reproduces the missing
        // path without discarding its Finder metadata or requiring a physical external drive.
        try FileManager.default.moveItem(atPath: project, toPath: offline)
        XCTAssertEqual(sync.sync(desired: [:]), 0)
        XCTAssertEqual(sync.loadRecord()[project], ["drums"])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: data + "/findertags.cfg")), saved)

        try FileManager.default.moveItem(atPath: offline, toPath: project)
        XCTAssertEqual(FinderTagSync(dataDir: data).sync(desired: [:]), 1)
        XCTAssertEqual(try tags(of: project), ["mine"])
        XCTAssertTrue(sync.loadRecord().isEmpty)
    }

    func testUnchangedAndCancelledSyncDoNotRewriteTheOwnershipRecord() throws {
        let data = try scratch()
        let project = try scratch()
        let sync = FinderTagSync(dataDir: data)
        XCTAssertEqual(sync.sync(desired: [project: ["drums"]]), 1)
        let recordPath = data + "/findertags.cfg"
        // An old mtime makes an otherwise identical atomic replacement observable reliably.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)],
                                             ofItemAtPath: recordPath)
        let saved = try XCTUnwrap(FileStat.of(recordPath))

        XCTAssertEqual(sync.sync(desired: [project: ["drums"]]), 0)
        XCTAssertEqual(FileStat.of(recordPath), saved)
        XCTAssertEqual(sync.sync(desired: [:], shouldContinue: { false }), 0)
        XCTAssertEqual(FileStat.of(recordPath), saved)
        XCTAssertEqual(try tags(of: project), ["drums"])
    }
}
