// Port of the calendar half of src/OverviewPanel.cs: a year of work, a column a week, a row a day
// (Monday on top), intensity by number of saves. The layout maths is pure; the view is a Canvas.
import SwiftUI

struct HeatmapCell: Equatable {
    let col: Int
    let row: Int
    let day: Date
    let saves: Int
}

/// The last 365 days laid out like GitHub's calendar.
struct HeatmapGrid {
    static let rows = 7
    /// Enough columns between two month captions for the captions not to run together.
    static let minMonthColumns = 3

    let from: Date
    let to: Date
    let cols: Int
    let cells: [HeatmapCell]
    /// The busiest day of the range (at least 1: it divides).
    let maxSaves: Int
    /// Columns where a month begins, left to right, already thinned out.
    let monthLabels: [(col: Int, month: Int)]
    private let firstColumnStart: Date
    private let calendar: Calendar

    /// Monday is zero: the week starts with it rather than with Sunday.
    static func weekday(_ day: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: day) + 5) % 7
    }

    static func make(today: Date, saves: (Date) -> Int, calendar: Calendar = .current) -> HeatmapGrid {
        let to = calendar.startOfDay(for: today)
        let from = calendar.date(byAdding: .day, value: -364, to: to) ?? to
        let firstCol = calendar.date(byAdding: .day, value: -weekday(from, calendar: calendar), to: from) ?? from
        let span = calendar.dateComponents([.day], from: firstCol, to: to).day ?? 0
        let cols = span / 7 + 1

        var cells: [HeatmapCell] = []
        var maxSaves = 1
        var day = from
        while day <= to {
            let offset = calendar.dateComponents([.day], from: firstCol, to: day).day ?? 0
            let n = saves(day)
            maxSaves = max(maxSaves, n)
            cells.append(HeatmapCell(col: offset / 7, row: offset % 7, day: day, saves: n))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        var grid = HeatmapGrid(from: from, to: to, cols: cols, cells: cells, maxSaves: maxSaves,
                               monthLabels: [], firstColumnStart: firstCol, calendar: calendar)
        grid = grid.withMonthLabels()
        return grid
    }

    private init(from: Date, to: Date, cols: Int, cells: [HeatmapCell], maxSaves: Int,
                 monthLabels: [(col: Int, month: Int)], firstColumnStart: Date, calendar: Calendar) {
        self.from = from; self.to = to; self.cols = cols; self.cells = cells; self.maxSaves = maxSaves
        self.monthLabels = monthLabels; self.firstColumnStart = firstColumnStart; self.calendar = calendar
    }

    /// Month captions over the columns where a month begins. Going RIGHT TO LEFT and skipping
    /// the ones that run into an already kept caption: otherwise the first column is still last
    /// December while the second is already January, and the two captions ran together. Going
    /// right to left what gets skipped is the stub on the left, not the full month on the right.
    private func withMonthLabels() -> HeatmapGrid {
        var starts: [(col: Int, month: Int)] = []
        var last = -1
        for c in 0..<cols {
            let month = calendar.component(.month, from: firstColumnStart.addingDays(c * 7, calendar))
            if month == last { continue }
            last = month
            starts.append((c, month))
        }
        var kept: [(col: Int, month: Int)] = []
        for item in starts.reversed() where kept.last.map({ $0.col - item.col >= Self.minMonthColumns }) ?? true {
            kept.append(item)
        }
        return HeatmapGrid(from: from, to: to, cols: cols, cells: cells, maxSaves: maxSaves,
                           monthLabels: kept.reversed(), firstColumnStart: firstColumnStart, calendar: calendar)
    }

    /// The cell under a grid position, or nil outside the range.
    func cell(col: Int, row: Int) -> HeatmapCell? {
        guard col >= 0, row >= 0, row < Self.rows else { return nil }
        let day = firstColumnStart.addingDays(col * 7 + row, calendar)
        guard day >= from, day <= to else { return nil }
        return cells.first { $0.col == col && $0.row == row }
    }

    /// Intensity 0...3 by the square root of the share of the busiest day: a straight proportion
    /// would let one day with 28 saves squash the rest of the scale into the palest level.
    /// nil for an empty day.
    static func level(saves: Int, maxSaves: Int) -> Int? {
        guard saves > 0 else { return nil }
        let step = Int(3.999 * (Double(saves) / Double(max(1, maxSaves))).squareRoot())
        return max(0, min(3, step))
    }

    static let levelAlpha: [Double] = [0x4C, 0x80, 0xB8, 0xF4].map { $0 / 255 }
    static let emptyAlpha = Double(0x1A) / 255
}

private extension Date {
    func addingDays(_ n: Int, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: n, to: self) ?? self
    }
}

/// The cell size that makes the grid fit the width (never smaller than 7 or larger than 14 pt at
/// 100 %; every size follows the interface scale, so these are computed, not stored).
struct HeatmapMetrics: Equatable {
    static var gap: CGFloat { Theme.s(3) }
    static var minCell: CGFloat { Theme.s(7) }
    static var maxCell: CGFloat { Theme.s(14) }

    let cell: CGFloat
    var step: CGFloat { cell + Self.gap }

    init(cols: Int, available: CGFloat) {
        let fit = (available - Self.gap * CGFloat(cols - 1)) / CGFloat(max(1, cols))
        cell = max(Self.minCell, min(Self.maxCell, fit.rounded(.down)))
    }

    func width(cols: Int) -> CGFloat { CGFloat(cols) * step - Self.gap }
    var height: CGFloat { CGFloat(HeatmapGrid.rows) * step - Self.gap }

    /// Where a cell is drawn, in the canvas's coordinates (below the month captions).
    func rect(col: Int, row: Int) -> CGRect {
        CGRect(x: CGFloat(col) * step, y: HeatmapFit.gridTop + CGFloat(row) * step, width: cell, height: cell)
    }
}

extension HeatmapGrid {
    /// The cell under a point of the canvas, or nil between cells, over the captions and outside the range.
    func cell(at point: CGPoint, metrics m: HeatmapMetrics) -> HeatmapCell? {
        let y = point.y - HeatmapFit.gridTop
        guard point.x >= 0, y >= 0, point.x.truncatingRemainder(dividingBy: m.step) < m.cell,
              y.truncatingRemainder(dividingBy: m.step) < m.cell else { return nil }
        return cell(col: Int(point.x / m.step), row: Int(y / m.step))
    }
}

/// A day of the calendar that was clicked: where its list opens and what it holds.
struct HeatmapDayPick: Identifiable {
    let cell: HeatmapCell
    let rect: CGRect
    let projects: [DayProject]
    var id: Date { cell.day }
}

/// Sizes its one child to the calendar for the proposed width, without any state feedback: a
/// size measured into @State made the window's structural-region pass loop at start-up.
struct HeatmapFit: Layout {
    let cols: Int
    /// The interface scale the sizes below were read at. A layout is not observed: a new value makes
    /// SwiftUI measure the calendar again after a change of Settings → Interface scale.
    let scale: CGFloat

    static var monthH: CGFloat { Theme.s(17) }
    static var monthGap: CGFloat { Theme.s(7) }
    /// Where the first row of cells begins.
    static let gridTop = monthH + monthGap

    static func size(cols: Int, available: CGFloat) -> CGSize {
        let m = HeatmapMetrics(cols: cols, available: available)
        return CGSize(width: m.width(cols: cols), height: monthH + monthGap + m.height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Self.size(cols: cols, available: proposal.width ?? 700)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let size = Self.size(cols: cols, available: bounds.width)
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}

struct ActivityHeatmap: View {
    @Environment(AppModel.self) private var app
    let grid: HeatmapGrid
    @Binding var hovered: HeatmapCell?
    /// The day whose projects are listed (a click on a day with saves, a6c8dc1).
    @State private var pick: HeatmapDayPick?

    var body: some View {
        HeatmapFit(cols: grid.cols, scale: ThemeScale.shared.factor) {
            GeometryReader { proxy in
                // The cell size is recovered from the size we were given: width = cols * step - gap.
                let m = HeatmapMetrics(cols: grid.cols, available: proxy.size.width)
                let monthFont = Theme.fGlyph(12)
                Canvas { context, _ in draw(&context, m, monthFont: monthFont) }
                    .onContinuousHover { phase in hover(phase, m) }
                    .onTapGesture { point in tap(at: point, m) }
                    .dayPointer(hovered.map { $0.saves > 0 } ?? false)
                    .popover(item: $pick, attachmentAnchor: .rect(.rect(pick?.rect ?? .zero)), arrowEdge: .bottom) { pick in
                        DayProjectsList(pick: pick) { path in
                            self.pick = nil
                            app.home.show(path: path)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeStrings.activeDays.s)
    }

    private var gridTop: CGFloat { HeatmapFit.gridTop }

    /// A day with saves opens the list of its projects; an empty day has nothing to open.
    private func tap(at point: CGPoint, _ m: HeatmapMetrics) {
        guard let cell = grid.cell(at: point, metrics: m), cell.saves > 0 else { return }
        pick = HeatmapDayPick(cell: cell, rect: m.rect(col: cell.col, row: cell.row),
                              projects: app.home.dayProjects(on: cell.day))
    }

    /// `monthFont` is 12 pt medium (scaled), so the captions stay readable at the calendar's real size.
    private func draw(_ context: inout GraphicsContext, _ m: HeatmapMetrics, monthFont: Font) {
        for label in grid.monthLabels {
            let text = context.resolve(Text(monthName(label.month)).font(monthFont).foregroundStyle(Theme.secondaryText))
            let width = m.width(cols: grid.cols)
            let labelWidth = text.measure(in: CGSize(width: width, height: HeatmapFit.monthH)).width
            let x = max(0, min(CGFloat(label.col) * m.step, width - labelWidth))
            context.draw(text, at: CGPoint(x: x, y: 0), anchor: .topLeading)
        }
        let radius = m.cell * 0.3
        for cell in grid.cells {
            let rect = CGRect(x: CGFloat(cell.col) * m.step, y: gridTop + CGFloat(cell.row) * m.step, width: m.cell, height: m.cell)
            let level = HeatmapGrid.level(saves: cell.saves, maxSaves: grid.maxSaves)
            let color = level.map { Theme.light.opacity(HeatmapGrid.levelAlpha[$0]) } ?? Color.white.opacity(HeatmapGrid.emptyAlpha)
            context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
        }
        if let hovered {
            let rect = CGRect(x: CGFloat(hovered.col) * m.step, y: gridTop + CGFloat(hovered.row) * m.step,
                              width: m.cell, height: m.cell).insetBy(dx: -Theme.s(1), dy: -Theme.s(1))
            context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(Theme.lightTop))
        }
    }

    private func hover(_ phase: HoverPhase, _ m: HeatmapMetrics) {
        switch phase {
        case .active(let point):
            let next = grid.cell(at: point, metrics: m)
            if next != hovered { hovered = next }
        case .ended:
            if hovered != nil { hovered = nil }
        }
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localizer.shared.locale
        let names = formatter.shortMonthSymbols ?? []
        return names.indices.contains(month - 1) ? names[month - 1] : ""
    }
}
