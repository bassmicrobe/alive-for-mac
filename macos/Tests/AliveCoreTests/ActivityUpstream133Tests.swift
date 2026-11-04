import XCTest
@testable import AliveCore

/// Upstream a6c8dc1: the history remembers which project every save was made in.
final class ActivityUpstream133Tests: XCTestCase {
    private let cal = Calendar.current
    private func at(_ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: d, hour: hour))!
    }
    private func mark(_ d: Int, hour: Int = 12, _ project: String) -> Activity.Mark {
        Activity.Mark(when: at(d, hour: hour), project: project)
    }

    /// The day's folders, busiest first, equal counts in the order of the first save — and they
    /// survive the cache.
    func testProjectsOfADayComeBackBusiestFirstAfterTheCache() {
        let t = makeTemp()
        let a = Activity(marks: [
            mark(3, hour: 9, "/P/Quiet Project"),
            mark(3, hour: 10, "/P/Busy Project"),
            mark(3, hour: 11, "/p/busy project"),          // the same folder, spelled otherwise
            mark(3, hour: 12, "/P/Busy Project"),
            mark(3, hour: 13, ""),                          // a save with no folder names nothing
            mark(4, hour: 9, "/P/Other Project"),
        ], today: at(10))
        a.saveCache(dir: t.path)
        let b = Activity.loadCache(dir: t.path, now: at(10))

        for history in [a, b] {
            XCTAssertEqual(history.projects(on: at(3, hour: 1)), ["/P/Busy Project", "/P/Quiet Project"])
            XCTAssertEqual(history.projects(on: at(4)), ["/P/Other Project"])
            XCTAssertEqual(history.projects(on: at(5)), [])
            XCTAssertEqual(history.total, 6)
        }
    }

    /// A history from before folders were kept reads as before, names nothing, and gets the
    /// folder of a moment the next walk finds again in a Backup folder. The file with folders is
    /// the old layout plus a tail.
    func testAnOldHistoryIsReadAndNamedByTheNextWalk() throws {
        let t = makeTemp()
        let when = at(2, hour: 9)
        var old = DotNetWriter()
        old.int32(Activity.cacheVersion); old.int32(1); old.int64(DotNetTicks.local(when))
        try old.data.write(to: URL(fileURLWithPath: Activity.cachePath(dir: t.path)))

        let previous = Activity.loadCache(dir: t.path, now: at(10))
        XCTAssertEqual(previous.total, 1)
        XCTAssertEqual(previous.projects(on: at(2)), [])

        var weight = FolderScan.Weight()
        weight.saves = [FolderScan.Save(when: when, set: "song")]
        let built = Activity.build(dirs: ["/P/Song Project"], weights: [weight], sets: [], previous: previous, now: at(10))
        XCTAssertEqual(built.total, 1, "the moment is not counted twice")
        XCTAssertEqual(built.projects(on: at(2)), ["/P/Song Project"])

        // What an older Alive reads out of the new file: version, count, the moments.
        built.saveCache(dir: t.path)
        var r = DotNetReader(try Data(contentsOf: URL(fileURLWithPath: Activity.cachePath(dir: t.path))))
        XCTAssertEqual(try r.int32(), Activity.cacheVersion)
        XCTAssertEqual(try r.int32(), 1)
        XCTAssertEqual(try r.int64(), DotNetTicks.local(when))
        XCTAssertEqual(try r.int32(), Activity.projectsMark, "the folders follow as a tail it does not reach")
    }

    /// A damaged moment is skipped on reading, and the folders of the moments after it must not
    /// slide onto the wrong ones.
    func testASkippedMomentDoesNotShiftTheFolders() throws {
        let t = makeTemp()
        let first = at(2, hour: 9), second = at(2, hour: 10)
        var w = DotNetWriter()
        w.int32(Activity.cacheVersion); w.int32(3)
        w.int64(DotNetTicks.local(first)); w.int64(Int64.max); w.int64(DotNetTicks.local(second))
        w.int32(Activity.projectsMark)
        w.string("/P/A Project"); w.string("/P/Lost Project"); w.string("/P/B Project")
        try w.data.write(to: URL(fileURLWithPath: Activity.cachePath(dir: t.path)))

        let a = Activity.loadCache(dir: t.path, now: at(10))
        XCTAssertEqual(a.total, 2)
        XCTAssertEqual(a.marks.map(\.project), ["/P/A Project", "/P/B Project"])
    }
}
