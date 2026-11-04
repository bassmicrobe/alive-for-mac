// Port of the keyboard and selection logic of CalendarPopup.MonthGrid (src/Controls.cs, 9ce4b4b and
// a6c8dc1), without the drawing: which month is on show, which day the keyboard stands on, and
// which day the date field holds. Pure, so it is tested without a window.
import Foundation
import SwiftUI

struct CalendarState: Equatable {
    var calendar: Calendar
    /// The field's date; nil while the field is empty. An empty field picks nothing, so no day is
    /// painted as picked (today keeps only its ring) — a picked today could not be told from it.
    let selected: Date?
    /// The day the keyboard stands on; Return picks it.
    private(set) var cursor: Date
    /// The first day of the month on show.
    private(set) var month: Date

    init(selected: Date?, today: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        self.selected = selected
        let start = calendar.startOfDay(for: selected ?? today)
        cursor = start
        month = Self.firstOfMonth(start, calendar)
    }

    /// What a key does, as the native month calendar did: arrows walk the days, Page Up / Page Down
    /// the months, Home / End the ends of the month.
    enum Move: Equatable {
        case days(Int), months(Int), startOfMonth, endOfMonth

        init?(key: KeyEquivalent) {
            switch key {
            case .leftArrow: self = .days(-1)
            case .rightArrow: self = .days(1)
            case .upArrow: self = .days(-7)
            case .downArrow: self = .days(7)
            case .pageUp: self = .months(-1)
            case .pageDown: self = .months(1)
            case .home: self = .startOfMonth
            case .end: self = .endOfMonth
            default: return nil
            }
        }
    }

    mutating func move(_ move: Move) {
        switch move {
        case .days(let n): cursor = calendar.date(byAdding: .day, value: n, to: cursor) ?? cursor
        case .months(let n): cursor = calendar.date(byAdding: .month, value: n, to: cursor) ?? cursor
        case .startOfMonth: cursor = Self.firstOfMonth(cursor, calendar)
        case .endOfMonth:
            let first = Self.firstOfMonth(cursor, calendar)
            let days = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
            cursor = calendar.date(byAdding: .day, value: days - 1, to: first) ?? cursor
        }
        month = Self.firstOfMonth(cursor, calendar)
    }

    /// The header arrows turn the page without moving the keyboard's day.
    mutating func showMonth(offset: Int) {
        month = calendar.date(byAdding: .month, value: offset, to: month) ?? month
    }

    /// Six weeks, starting on the calendar's first weekday, so the grid never changes height.
    var days: [Date] {
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let first = calendar.date(byAdding: .day, value: -lead, to: month) ?? month
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    func isSelected(_ day: Date) -> Bool { selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
    func isCursor(_ day: Date) -> Bool { calendar.isDate(cursor, inSameDayAs: day) }
    func isInShownMonth(_ day: Date) -> Bool { calendar.isDate(day, equalTo: month, toGranularity: .month) }

    private static func firstOfMonth(_ day: Date, _ calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
    }
}
