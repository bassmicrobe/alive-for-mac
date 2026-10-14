import XCTest
@testable import AliveCore

/// A sample folder on a disconnected drive is neither walked as empty nor dropped, and the sets that
/// point at its samples keep counting as users.
final class SampleOfflineRootTests: XCTestCase {
    private let ghost = "/Volumes/GhostDrive/Lib"
    private let mounted: Set<String> = ["Macintosh HD"]

    /// A cached tree for the ghost root, made by walking a real folder and moving its paths.
    private func cachedGhost(_ t: TempDir) -> SampleIndex {
        t.write("Lib/Drums/kick.wav", "kick")
        t.write("Lib/Drums/snare.wav", "snare!")
        var idx = SampleIndex.walk(root: t.sub("Lib"), known: nil, found: { _ in }, isCancelled: { false })!
        for i in idx.folders.indices {
            idx.folders[i].path = ghost + idx.folders[i].path.dropFirst(t.sub("Lib").count)
        }
        return idx
    }

    func testAnOfflineRootKeepsItsCachedTree() throws {
        let t = makeTemp("offline-samples")
        let previous = cachedGhost(t)
        let local = t.mkdir("Local")
        t.write("Local/loop.wav", "loop")

        let built = SampleIndex.build(roots: [ghost, local], disabled: [], previous: previous, mounted: mounted)
        XCTAssertEqual(built.roots.count, 2)
        XCTAssertEqual(built.totalSamples, 3, "2 cached + 1 walked")
        let ghostRoot = try XCTUnwrap(built.roots.first { built.folders[$0].path == ghost })
        XCTAssertEqual(built.folders[ghostRoot].totalSamples, 2)
        XCTAssertEqual(built.folders[ghostRoot].totalBytes, 10)
    }

    func testAnOfflineRootNeverWalkedStaysListedEmpty() {
        let built = SampleIndex.build(roots: [ghost], disabled: [], previous: nil, mounted: mounted)
        XCTAssertEqual(built.roots.count, 1)
        XCTAssertEqual(built.folders[built.roots[0]].path, ghost)
        XCTAssertEqual(built.totalSamples, 0)
    }

    func testTheSameRootWalksForRealOnceTheVolumeIsBack() {
        let t = makeTemp("offline-samples")
        let previous = cachedGhost(t)
        // "Mounted" but nothing there: the walk finds the folder unreadable, as before this change.
        let built = SampleIndex.build(roots: [ghost], disabled: [], previous: previous,
                                      mounted: mounted.union(["GhostDrive"]))
        XCTAssertTrue(built.roots.isEmpty)
    }

    func testWithoutVolumeKnowledgeEveryRootIsWalked() {
        let t = makeTemp("offline-samples")
        let previous = cachedGhost(t)
        let built = SampleIndex.build(roots: [ghost], disabled: [], previous: previous, mounted: nil)
        XCTAssertTrue(built.roots.isEmpty)
    }

    func testSetsStillUseSamplesOnTheDisconnectedDrive() throws {
        let t = makeTemp("offline-samples")
        let index = SampleIndex.combining([cachedGhost(t)])
        var set = SetEntry()
        set.path = "/m/A Project/A.als"
        set.modified = Date()
        let kick = ghost + "/Drums/kick.wav"

        XCTAssertEqual(SampleUsage.compute(index: index, sets: [set]).usedCount, 0)
        let usage = SampleUsage.compute(index: index, sets: [set], offlineReferences: [set.path: [kick]])
        XCTAssertEqual(usage.usedCount, 1)
        let file = try XCTUnwrap(usage.usedFiles.first)
        XCTAssertEqual(index.files[file].name, "kick.wav")
        XCTAssertEqual(usage.of(file: file)?.projects, 1)
    }
}
