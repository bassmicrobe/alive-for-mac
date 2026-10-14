import XCTest
@testable import AliveCore

final class WidgetSnapshotTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    /// Wednesday 2026-10-14, 15:00 Tokyo.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 15))! }

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        let d = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
        return cal.date(byAdding: .hour, value: hour, to: d)!
    }

    private func entry(_ name: String, project: String, modified: Date, backup: Bool = false) -> SetEntry {
        var e = SetEntry()
        e.path = "/Music/\(project) Project/\(name).als"
        e.name = name
        e.projectName = project
        e.modified = modified
        e.isBackup = backup
        return e
    }

    private func snapshot() -> WidgetSnapshot {
        // Saves today (2), yesterday (1), two days ago (3), then a gap.
        let stamps = [day(0, hour: 9), day(0, hour: 12), day(-1), day(-2, hour: 8), day(-2, hour: 9), day(-2, hour: 10), day(-10)]
        let activity = Activity(stamps: stamps, today: now)
        let sets = [
            entry("a", project: "Old", modified: day(-9)),
            entry("b", project: "New", modified: day(0)),
            entry("b2", project: "New", modified: day(-1)),            // same folder as b: one row for the project
            entry("c", project: "Mid", modified: day(-3), backup: false),
            entry("backup", project: "Zed", modified: day(0), backup: true),
        ]
        return WidgetSnapshot.make(activity: activity, sets: sets, now: now, calendar: cal)
    }

    func testMakeCopiesStreaksAndCountsDays() {
        let s = snapshot()
        XCTAssertEqual(s.version, WidgetSnapshot.currentVersion)
        XCTAssertEqual(s.currentStreak, 3)
        XCTAssertEqual(s.activeDays, 4)
        XCTAssertEqual(s.savesToday(now: now, calendar: cal), 2)
        XCTAssertEqual(s.lastActiveDay, cal.startOfDay(for: now))
    }

    func testRecentAreProjectsNewestFirstWithoutBackups() {
        let names = snapshot().recent.map(\.name)
        XCTAssertEqual(names, ["b", "c", "a"])
    }

    func testRecentIsCappedAtFive() {
        let sets = (0..<9).map { entry("s\($0)", project: "P\($0)", modified: day(-$0)) }
        let s = WidgetSnapshot.make(activity: .empty, sets: sets, now: now, calendar: cal)
        XCTAssertEqual(s.recent.count, WidgetSnapshot.recentCount)
    }

    func testEncodeDecodeRoundTrip() throws {
        let original = snapshot()
        let decoded = try XCTUnwrap(WidgetSnapshot.decode(try original.encoded()))
        XCTAssertTrue(decoded.sameContent(as: original))
        XCTAssertEqual(decoded.days, original.days)
        XCTAssertEqual(decoded.recent, original.recent)
    }

    func testDecodeRejectsDamagedAndFutureData() throws {
        XCTAssertNil(WidgetSnapshot.decode(Data("not json".utf8)))
        XCTAssertNil(WidgetSnapshot.decode(Data()))
        var future = snapshot()
        future.version = WidgetSnapshot.currentVersion + 1
        XCTAssertNil(WidgetSnapshot.decode(try future.encoded()))
    }

    func testSameContentIgnoresTheClockOnly() {
        let a = snapshot()
        var b = a
        b.generatedAt = a.generatedAt.addingTimeInterval(3600)
        XCTAssertTrue(a.sameContent(as: b))
        b.currentStreak += 1
        XCTAssertFalse(a.sameContent(as: b))
    }

    func testStreakLapsesWhenSnapshotIsOld() {
        let s = snapshot()
        XCTAssertEqual(s.streak(now: now, calendar: cal), 3)
        XCTAssertEqual(s.streak(now: day(1), calendar: cal), 3)       // saved yesterday: still alive
        XCTAssertEqual(s.streak(now: day(2), calendar: cal), 0)       // two days without a save
        XCTAssertEqual(s.savesToday(now: day(1), calendar: cal), 0)
    }

    func testHeatmapIsTwelveMondayFirstWeeksEndingToday() {
        let grid = snapshot().heatmap(now: now, calendar: cal)
        XCTAssertEqual(grid.count, WidgetSnapshot.heatmapWeeks)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
        // Wednesday: the last column is Mon, Tue, Wed (today) with Thu...Sun still to come.
        let last = grid[grid.count - 1]
        XCTAssertEqual(last[2].date, cal.startOfDay(for: now))
        XCTAssertEqual(last[2].saves, 2)
        XCTAssertEqual(last[1].saves, 1)                               // yesterday
        XCTAssertEqual(last[0].saves, 3)                               // two days ago
        XCTAssertTrue(last[3...].allSatisfy { $0.saves == nil })
        XCTAssertEqual(cal.component(.weekday, from: grid[0][0].date), 2)   // Monday
        XCTAssertEqual(grid[0][0].saves, 0)
    }

    func testWidgetFileLivesInItsOwnSubfolderOfTheDefaultDataFolder() {
        let url = WidgetSnapshot.widgetFileURL(realHome: "/Users/someone")
        XCTAssertEqual(url.path, "/Users/someone/Library/Application Support/Alive for Mac/widget/widget.json")
    }

    func testOnlyRecentDaysAreKept() {
        let activity = Activity(stamps: [day(-400), day(0)], today: now)
        let s = WidgetSnapshot.make(activity: activity, sets: [], now: now, calendar: cal)
        XCTAssertEqual(s.days.count, 1)
        XCTAssertEqual(s.activeDays, 2)
    }
}
