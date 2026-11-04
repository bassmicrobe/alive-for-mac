import XCTest
@testable import AliveCore

/// Upstream a6c8dc1: the sample library is walked at start only when it has to be.
final class SamplesUpstream133Tests: XCTestCase {
    private func cached(_ roots: [String]) -> SampleIndex {
        var idx = SampleIndex()
        for r in roots {
            var f = SampleFolder()
            f.path = r; f.name = r
            idx.roots.append(idx.folders.count)
            idx.folders.append(f)
        }
        return idx
    }

    func testAStartWalksOnlyWhenTheLastWalkIsOldOrAFolderIsMissing() {
        let now = Date()
        let hoursAgo = { (h: Double) in now.addingTimeInterval(-h * 3600) }
        let index = cached(["/lib/A"])
        func due(_ roots: [String], disabled: [String] = [], walked: Date?) -> Bool {
            SampleIndex.walkDue(cached: index, roots: roots, disabled: disabled, walkedAt: walked, now: now)
        }

        XCTAssertFalse(due(["/lib/A"], walked: hoursAgo(3)), "walked this morning, nothing new")
        XCTAssertFalse(due(["/LIB/a/"], walked: hoursAgo(3)), "the same folder spelled otherwise")
        XCTAssertFalse(due(["/lib/A", "/lib/A/sub"], walked: hoursAgo(3)), "a folder inside another is not a root of its own")
        XCTAssertFalse(due(["/lib/A", "/lib/B"], disabled: ["/lib/B"], walked: hoursAgo(3)), "a folder switched off is not missing")

        XCTAssertTrue(due(["/lib/A"], walked: hoursAgo(25)), "over a day old")
        XCTAssertTrue(due(["/lib/A"], walked: nil), "never walked")
        XCTAssertTrue(due(["/lib/A"], walked: now.addingTimeInterval(3 * 86_400)), "a walk dated in the future cannot be trusted")
        XCTAssertTrue(due(["/lib/A", "/lib/B"], walked: hoursAgo(3)), "a folder the cache lacks")
    }

    /// The time is kept behind the roots: the version is the same, and a copy of Alive from before
    /// reads the file as ever. A touch of the file by a backup tool changes nothing; a cache from
    /// before the time was kept falls back to the file's own date, like upstream.
    func testTheWalkTimeIsKeptInTheCacheWithoutChangingItsFormat() throws {
        let t = makeTemp()
        let index = cached(["/lib/A"])
        XCTAssertNil(SampleCache.walkedAt(dir: t.path), "no cache, no walk")

        let walked = Date().addingTimeInterval(-5 * 3600)
        SampleCache.save(index, dir: t.path, walked: walked)
        let file = SampleCache.path(dir: t.path)
        XCTAssertEqual(try XCTUnwrap(SampleCache.walkedAt(dir: t.path)).timeIntervalSince1970, walked.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(SampleCache.load(dir: t.path).roots.count, 1, "read as before")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: file)).prefix(SampleCache.encode(index).count),
                       SampleCache.encode(index), "the old layout is untouched, the time only follows it")

        t.setModified(file, Date())                 // somebody copies or restores the file
        XCTAssertEqual(try XCTUnwrap(SampleCache.walkedAt(dir: t.path)).timeIntervalSince1970, walked.timeIntervalSince1970, accuracy: 0.001)

        let modified = Date().addingTimeInterval(-7200)
        try SampleCache.encode(index).write(to: URL(fileURLWithPath: file))      // written by 0.3.2
        t.setModified(file, modified)
        XCTAssertEqual(try XCTUnwrap(SampleCache.walkedAt(dir: t.path)).timeIntervalSince1970, modified.timeIntervalSince1970, accuracy: 1)
    }
}
