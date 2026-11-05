import SwiftUI
import XCTest
@testable import AliveUI

/// The month grid under the filters' date fields (9ce4b4b, a6c8dc1).
final class SetsCalendarUpstream133Tests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2          // Monday, so the grid's first column is known
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testAnEmptyFieldOpensOnTodayWithNoDayPicked() {
        let today = day(2026, 11, 4)
        let empty = CalendarState(selected: nil, today: today, calendar: calendar)
        XCTAssertTrue(empty.days.allSatisfy { !empty.isSelected($0) })
        XCTAssertTrue(empty.isCursor(today))
        XCTAssertEqual(empty.days.count, 42)
        XCTAssertEqual(calendar.component(.weekday, from: empty.days[0]), calendar.firstWeekday)

        let filled = CalendarState(selected: day(2026, 8, 7), today: today, calendar: calendar)
        XCTAssertEqual(filled.days.filter(filled.isSelected), [day(2026, 8, 7)])
        XCTAssertTrue(filled.isCursor(day(2026, 8, 7)))
    }

    func testTheKeysMoveLikeTheSystemCalendar() {
        var state = CalendarState(selected: nil, today: day(2026, 1, 31), calendar: calendar)
        state.move(.init(key: .rightArrow)!)
        XCTAssertTrue(state.isCursor(day(2026, 2, 1)))
        XCTAssertTrue(state.isInShownMonth(day(2026, 2, 14)), "the month follows the cursor")
        state.move(.init(key: .downArrow)!)
        XCTAssertTrue(state.isCursor(day(2026, 2, 8)))
        state.move(.init(key: .pageDown)!)
        XCTAssertTrue(state.isCursor(day(2026, 3, 8)))
        state.move(.init(key: .end)!)
        XCTAssertTrue(state.isCursor(day(2026, 3, 31)))
        state.move(.init(key: .pageUp)!)
        XCTAssertTrue(state.isCursor(day(2026, 2, 28)), "a month back from the 31st lands on the month's last day")
        state.move(.init(key: .home)!)
        XCTAssertTrue(state.isCursor(day(2026, 2, 1)))
        XCTAssertNil(CalendarState.Move(key: .return))
    }
}
