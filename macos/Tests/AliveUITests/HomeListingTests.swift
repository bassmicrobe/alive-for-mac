import XCTest
@testable import AliveCore
@testable import AliveUI

final class HomeListingTests: XCTestCase {
    private func entry(_ path: String, name: String? = nil, age: Double, backup: Bool = false) -> SetEntry {
        var e = SetEntry()
        e.path = path
        e.name = name ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        e.projectName = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        e.modified = Date(timeIntervalSince1970: 2_000_000_000 - age)
        e.isBackup = backup
        return e
    }

    private var sets: [SetEntry] {
        [
            entry("/p/Alpha Project/alpha.als", age: 10),
            entry("/p/Alpha Project/alpha v2.als", age: 5),      // newer version of the same folder
            entry("/p/Beta Project/beta.als", age: 30),
            entry("/p/Gamma Project/gamma.als", age: 20),
            entry("/p/Gamma Project/Backup/gamma [2024].als", age: 1, backup: true),
        ]
    }

    private func names(_ list: [SetEntry]) -> [String] { list.map(\.name) }

    func testNewestFirstOneTilePerFolderWithoutBackups() {
        let out = HomeListing.projects(sets: sets, query: "", groupByFolder: true, pinOrder: [], pinnedFirst: false)
        XCTAssertEqual(names(out), ["alpha v2", "gamma", "beta"])
        XCTAssertEqual(out.first?.collapsedCount, 1)
    }

    func testUngroupedShowsEveryVersion() {
        let out = HomeListing.projects(sets: sets, query: "", groupByFolder: false, pinOrder: [], pinnedFirst: false)
        XCTAssertEqual(names(out), ["alpha v2", "alpha", "gamma", "beta"])
    }

    func testSearchFiltersBeforeFolding() {
        // "final mix" is the newest version of the folder, but only the older "sketch" matches.
        let versions = [entry("/p/Delta Project/sketch.als", age: 50), entry("/p/Delta Project/final mix.als", age: 2)]
        let out = HomeListing.projects(sets: versions, query: "sketch", groupByFolder: true, pinOrder: [], pinnedFirst: false)
        XCTAssertEqual(names(out), ["sketch"])
        XCTAssertTrue(HomeListing.projects(sets: sets, query: "zzz", groupByFolder: true, pinOrder: [], pinnedFirst: false).isEmpty)
        XCTAssertEqual(HomeListing.projects(sets: sets, query: "BETA", groupByFolder: true, pinOrder: [], pinnedFirst: false).count, 1)
    }

    func testPinnedFirstFollowsPinOrderNotDate() {
        let pins = ["/p/Beta Project/beta.als", "/p/Gamma Project/gamma.als"]
        let out = HomeListing.projects(sets: sets, query: "", groupByFolder: true, pinOrder: pins, pinnedFirst: true)
        XCTAssertEqual(names(out), ["beta", "gamma", "alpha v2"])
        let dated = HomeListing.projects(sets: sets, query: "", groupByFolder: true, pinOrder: pins, pinnedFirst: false)
        XCTAssertEqual(names(dated), ["alpha v2", "gamma", "beta"])
    }

    func testPinnedOldVersionComesBackWhenFolded() {
        let pins = ["/p/Alpha Project/alpha.als"]     // the collapsed, older version
        let out = HomeListing.projects(sets: sets, query: "", groupByFolder: true, pinOrder: pins, pinnedFirst: true)
        XCTAssertEqual(out.first?.name, "alpha")
        XCTAssertTrue(names(out).contains("alpha v2"))
    }

    func testPinLookupIgnoresCase() {
        let out = HomeListing.projects(sets: sets, query: "", groupByFolder: true,
                                       pinOrder: ["/P/BETA PROJECT/BETA.ALS"], pinnedFirst: true)
        XCTAssertEqual(out.first?.name, "beta")
    }

    func testTilesKeepTheirOrderOnEqualDates() {
        let same = [entry("/p/B/b.als", age: 5), entry("/p/A/a.als", age: 5)]
        let out = HomeListing.projects(sets: same, query: "", groupByFolder: true, pinOrder: [], pinnedFirst: false)
        XCTAssertEqual(out.map(\.path), ["/p/A/a.als", "/p/B/b.als"])
    }

    @MainActor
    func testSubtitleIsDateAndPlace() {
        var e = entry("/shelf/Song Project/song.als", age: 0)
        e.modified = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertTrue(HomeModel.subtitle(for: e).hasSuffix("shelf"))
        XCTAssertEqual(HomeModel.dateText(Date(timeIntervalSince1970: 0)).count, 10)
    }
}

final class HomeTileNavigationTests: XCTestCase {
    func testStartsAtTheFirstTile() {
        XCTAssertEqual(TileNavigation.move(from: nil, .right, columns: 4, count: 10), 0)
        XCTAssertNil(TileNavigation.move(from: nil, .right, columns: 4, count: 0))
    }

    func testFirstRowIsShiftedByTheNewSetTile() {
        // 4 columns: slot 0 is "New Live Set", sets take slots 1...; index 3 is slot 4, the start of row 2.
        XCTAssertEqual(TileNavigation.move(from: 0, .right, columns: 4, count: 10), 1)
        XCTAssertEqual(TileNavigation.move(from: 3, .down, columns: 4, count: 10), 7)
        XCTAssertEqual(TileNavigation.move(from: 4, .up, columns: 4, count: 10), 0)
        XCTAssertNil(TileNavigation.move(from: 0, .left, columns: 4, count: 10))
        XCTAssertNil(TileNavigation.move(from: 0, .up, columns: 4, count: 10))
    }

    func testDownFromTheLastRowsStopsAtTheLastTile() {
        XCTAssertEqual(TileNavigation.move(from: 7, .down, columns: 4, count: 10), 9)
        XCTAssertNil(TileNavigation.move(from: 9, .down, columns: 4, count: 10))
        XCTAssertNil(TileNavigation.move(from: 9, .right, columns: 4, count: 10))
    }

    func testColumnCountFollowsUpstream() {
        // (width + gap) / (250 + gap), at least 1
        XCTAssertEqual(HomeContentColumns.count(for: 100), 1)
        XCTAssertEqual(HomeContentColumns.count(for: 1000), 3)
        XCTAssertEqual(HomeContentColumns.count(for: 1150), 4)
        XCTAssertEqual(HomeContentColumns.count(for: 9000), 33)
    }

    func testKeyCodesMapToGridKeys() {
        XCTAssertEqual(HomeKeyMonitor.key(forCode: 36), .return)
        XCTAssertEqual(HomeKeyMonitor.key(forCode: 49), .space)
        XCTAssertEqual(HomeKeyMonitor.key(forCode: 123), .move(.left))
        XCTAssertEqual(HomeKeyMonitor.key(forCode: 126), .move(.up))
        XCTAssertNil(HomeKeyMonitor.key(forCode: 0), "letters are not ours")
    }
}
