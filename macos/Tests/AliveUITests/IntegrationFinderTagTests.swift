import XCTest
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

    func testMissingFolderIsForgottenNotCreated() throws {
        let data = try scratch()
        let gone = NSTemporaryDirectory() + "alive-ui-tests-missing-" + UUID().uuidString
        XCTAssertEqual(FinderTagSync(dataDir: data).sync(desired: [gone: ["x"]]), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gone))
    }
}
