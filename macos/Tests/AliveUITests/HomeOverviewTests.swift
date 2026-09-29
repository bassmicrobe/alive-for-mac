import XCTest
@testable import AliveCore
@testable import AliveUI

final class HomeOverviewTests: XCTestCase {
    // MARK: formatting

    func testDaysAndHours() {
        Localizer.shared.preference = .en
        defer { Localizer.shared.preference = .system }
        XCTAssertEqual(OverviewFormat.days(0), "—")
        XCTAssertEqual(OverviewFormat.days(4), "4d")
        XCTAssertEqual(OverviewFormat.hour(-1), "—")
        XCTAssertEqual(OverviewFormat.hour(23), "23:00")
        XCTAssertEqual(OverviewFormat.hour(7), "07:00")
    }

    func testNumbersAreGroupedWithSpaces() {
        XCTAssertEqual(OverviewFormat.number(93), "93")
        XCTAssertEqual(OverviewFormat.number(1234), "1 234")
        XCTAssertEqual(OverviewFormat.number(1_234_567), "1 234 567")
        XCTAssertEqual(OverviewFormat.number(0), "0")
    }

    func testBytesUseUpstreamUnits() {
        XCTAssertEqual(OverviewFormat.bytes(512), "0 KB")
        XCTAssertEqual(OverviewFormat.bytes(5 * 1024), "5 KB")
        XCTAssertEqual(OverviewFormat.bytes(300 * 1024 * 1024), "300 MB")
        XCTAssertEqual(OverviewFormat.bytes(21 * 1024 * 1024 * 1024), "21 GB")
        XCTAssertEqual(OverviewFormat.bytes(Int64(1.5 * 1024 * 1024 * 1024 * 1024)), "1.5 TB")
    }

    func testFooterAndHoverTextFollowTheLanguage() {
        Localizer.shared.preference = .en
        defer { Localizer.shared.preference = .system }
        XCTAssertEqual(OverviewFormat.footer(diskBytes: 21 * 1024 * 1024 * 1024), "21 GB on disk")
        XCTAssertEqual(OverviewFormat.footer(diskBytes: 0), "")
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertTrue(OverviewFormat.hover(day: day, saves: 0).hasPrefix("nothing saved"))
        XCTAssertTrue(OverviewFormat.hover(day: day, saves: 1).hasPrefix("1 save  ·"))
        XCTAssertTrue(OverviewFormat.hover(day: day, saves: 3).hasPrefix("3 saves  ·"))
        Localizer.shared.preference = .ja
        XCTAssertEqual(OverviewFormat.days(3), "3日")
        XCTAssertTrue(OverviewFormat.hover(day: day, saves: 2).contains("2 回保存"))
    }

    // MARK: stats

    func testDiskIsCountedPerFolderNotPerVersion() {
        func set(_ path: String, size: Int64, backup: Bool = false) -> SetEntry {
            var e = SetEntry()
            e.path = path
            e.projectSize = size
            e.isBackup = backup
            return e
        }
        let sets = [set("/p/A Project/a.als", size: 100), set("/p/A Project/a v2.als", size: 100),
                    set("/p/B Project/b.als", size: 50), set("/p/B Project/Backup/b.als", size: 999, backup: true)]
        XCTAssertEqual(OverviewStats.compute(history: .empty, sets: sets).diskBytes, 150)
        XCTAssertEqual(OverviewStats.compute(history: .empty, sets: []), OverviewStats(peakHour: -1))
    }

    // MARK: heatmap

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testGridCoversAYearWithMondayFirst() throws {
        let today = day(2026, 9, 29)                          // a Tuesday
        let grid = HeatmapGrid.make(today: today, saves: { _ in 0 }, calendar: calendar)
        XCTAssertEqual(grid.cells.count, 365)
        XCTAssertEqual(grid.to, today)
        XCTAssertEqual(calendar.dateComponents([.day], from: grid.from, to: grid.to).day, 364)
        XCTAssertTrue(grid.cols == 53 || grid.cols == 54)
        let last = try XCTUnwrap(grid.cells.last)
        XCTAssertEqual(last.row, 1, "Tuesday is the second row when Monday is zero")
        XCTAssertEqual(last.col, grid.cols - 1)
        XCTAssertEqual(HeatmapGrid.weekday(day(2026, 9, 28), calendar: calendar), 0)   // Monday
        XCTAssertEqual(HeatmapGrid.weekday(day(2026, 9, 27), calendar: calendar), 6)   // Sunday
        XCTAssertNotNil(grid.cell(col: last.col, row: last.row))
        XCTAssertNil(grid.cell(col: last.col, row: 5), "after today")
        XCTAssertNil(grid.cell(col: 0, row: 9))
    }

    func testMaxSavesAndLevels() {
        let busy = day(2026, 9, 1)
        let grid = HeatmapGrid.make(today: day(2026, 9, 29),
                                    saves: { $0 == busy ? 28 : $0 == self.day(2026, 9, 2) ? 1 : 0 }, calendar: calendar)
        XCTAssertEqual(grid.maxSaves, 28)
        XCTAssertNil(HeatmapGrid.level(saves: 0, maxSaves: 28))
        XCTAssertEqual(HeatmapGrid.level(saves: 28, maxSaves: 28), 3)
        XCTAssertEqual(HeatmapGrid.level(saves: 1, maxSaves: 28), 0)
        // The square root keeps a light day visible next to a heavy one.
        XCTAssertEqual(HeatmapGrid.level(saves: 7, maxSaves: 28), 1)
        XCTAssertEqual(HeatmapGrid.level(saves: 20, maxSaves: 28), 3)
        XCTAssertEqual(HeatmapGrid.level(saves: 5, maxSaves: 0), 3, "an empty range never divides by zero")
    }

    func testMonthLabelsDoNotRunTogether() {
        let grid = HeatmapGrid.make(today: day(2026, 9, 29), saves: { _ in 0 }, calendar: calendar)
        let cols = grid.monthLabels.map(\.col)
        XCTAssertEqual(cols, cols.sorted())
        for (a, b) in zip(cols, cols.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, HeatmapGrid.minMonthColumns) }
        XCTAssertEqual(grid.monthLabels.last?.month, 9)
        XCTAssertGreaterThanOrEqual(grid.monthLabels.count, 11)
    }

    func testCellSizeFitsTheWidth() {
        XCTAssertEqual(HeatmapMetrics(cols: 53, available: 2000).cell, 14)
        XCTAssertEqual(HeatmapMetrics(cols: 53, available: 100).cell, 7, "never smaller than 7")
        let m = HeatmapMetrics(cols: 53, available: 900)
        XCTAssertLessThanOrEqual(m.width(cols: 53), 900)
        XCTAssertEqual(m.height, 7 * m.step - 3)
    }

    func testOverviewContentWidthIsTwoThirdsOnWideWindows() {
        XCTAssertEqual(OverviewPanel.contentWidth(for: 500), 500)
        XCTAssertEqual(OverviewPanel.contentWidth(for: 800), 560)
        XCTAssertEqual(OverviewPanel.contentWidth(for: 1500), 1000)
    }
}
