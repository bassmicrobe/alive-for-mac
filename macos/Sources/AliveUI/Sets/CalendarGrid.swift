// Port of CalendarPopup.MonthGrid (src/Controls.cs, 9ce4b4b + a6c8dc1): the month under a date
// field. SwiftUI's graphical DatePicker always paints one day as picked, so an empty field could
// not open on "nothing picked"; this grid keeps `CalendarState`'s rules instead.
import SwiftUI
import AliveCore

struct CalendarGrid: View {
    let onPick: (Date) -> Void
    @State private var state: CalendarState
    @FocusState private var focused: Bool
    @State private var today = Date()

    private static let cell = CGSize(width: 34, height: 30)

    init(selected: Date?, onPick: @escaping (Date) -> Void) {
        var calendar = Calendar.current
        calendar.locale = Localizer.shared.locale
        _state = State(initialValue: CalendarState(selected: selected, today: Date(), calendar: calendar))
        self.onPick = onPick
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            weekdays
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell.width), spacing: 0), count: 7), spacing: 0) {
                ForEach(state.days, id: \.self) { day in
                    DayCell(day: day, state: state, isToday: state.calendar.isDate(day, inSameDayAs: today)) { onPick(day) }
                }
            }
            todayButton
        }
        .padding(12)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        // The keys go to the grid, not to the date field under the popover.
        .onAppear { focused = true }
        .onKeyPress(phases: [.down, .repeat]) { press in
            if press.key == .return { onPick(state.cursor); return .handled }
            guard press.modifiers.isEmpty, let move = CalendarState.Move(key: press.key) else { return .ignored }
            state.move(move)
            return .handled
        }
    }

    private var header: some View {
        HStack {
            arrow(.chevronDown, offset: -1, label: SetsStrings.calendarPrevious.s)
            Spacer()
            Text(state.month.formatted(.dateTime.year().month(.wide).locale(Localizer.shared.locale)))
                .font(Theme.fTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            arrow(.chevronDown, offset: 1, label: SetsStrings.calendarNext.s)
        }
    }

    private func arrow(_ icon: AppIcon, offset: Int, label: String) -> some View {
        Button { state.showMonth(offset: offset) } label: {
            IconView(icon: icon, size: 11)
                .rotationEffect(.degrees(offset < 0 ? 90 : -90))
                .foregroundStyle(Theme.text)
                .frame(width: Self.cell.width, height: Self.cell.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(Theme.fBadge)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: Self.cell.width)
            }
        }
        .accessibilityHidden(true)
    }

    /// The narrow weekday names, starting on the calendar's first weekday.
    private var weekdaySymbols: [String] {
        let calendar = state.calendar
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var todayButton: some View {
        Button { onPick(today) } label: {
            Text(SetsStrings.calendarToday.f(SetFilter.formatDate(today, calendar: state.calendar)))
                .font(Theme.fSmall)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, minHeight: Self.cell.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One day: filled when it is the field's date, lit when the keyboard stands on it, ringed
    /// when it is today, dim outside the month on show.
    private struct DayCell: View {
        let day: Date
        let state: CalendarState
        let isToday: Bool
        let pick: () -> Void
        @State private var hovering = false

        var body: some View {
            let selected = state.isSelected(day)
            Button(action: pick) {
                Text(state.calendar.component(.day, from: day).formatted(.number.locale(Localizer.shared.locale)))
                    .font(Theme.fSmall)
                    .monospacedDigit()
                    .foregroundStyle(selected ? Theme.onLight : state.isInShownMonth(day) ? Theme.text : Theme.secondaryText)
                    .frame(width: CalendarGrid.cell.width - 4, height: CalendarGrid.cell.height - 2)
                    .background(fill(selected), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        if isToday && !selected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.secondaryText, lineWidth: 1)
                        }
                    }
                    .frame(width: CalendarGrid.cell.width, height: CalendarGrid.cell.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel(day.formatted(.dateTime.year().month(.wide).day().locale(Localizer.shared.locale)))
            .accessibilityAddTraits(selected ? .isSelected : [])
        }

        private func fill(_ selected: Bool) -> Color {
            if selected { return Theme.light }
            return hovering || state.isCursor(day) ? Theme.surfacePressed : .clear
        }
    }
}
