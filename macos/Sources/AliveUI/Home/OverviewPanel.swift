// Port of src/OverviewPanel.cs: the summary above the project list — four stat cards, a calendar of
// the work and the weight of the library. Collapsible; the state is `settings.overviewOpen`.
import AliveCore
import SwiftUI

/// Numbers of the cards. Counted from the catalog's history and sets, memoized by `HomeModel`.
struct OverviewStats: Equatable {
    var activeDays = 0
    var streak = 0
    var record = 0
    /// 0...23, -1 when there is no history.
    var peakHour = -1
    var diskBytes: Int64 = 0

    static func compute(history: Activity, sets: [SetEntry]) -> OverviewStats {
        // The weight is counted by folders: a project has a dozen .als versions next to each
        // other, and by sets one and the same folder would be added ten times over.
        var seen = Set<String>()
        var disk: Int64 = 0
        for s in sets where !s.isBackup && !s.projectDir.isEmpty && seen.insert(s.projectDir.lowercased()).inserted {
            disk += s.projectSize
        }
        return OverviewStats(activeDays: history.activeDays, streak: history.currentStreak,
                             record: history.longestStreak, peakHour: history.peakHour, diskBytes: disk)
    }
}

/// Text of the overview. Pure so the wording and the units can be tested.
enum OverviewFormat {
    static let none = "—"

    static func days(_ n: Int) -> String { n <= 0 ? none : HomeStrings.daysShort.f(n) }

    static func hour(_ h: Int) -> String { h < 0 ? none : String(format: "%02d:00", h) }

    /// 12 345 → "12 345": groups of three digits, separated by a plain space like upstream.
    static func number(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0, i % 3 == 0 { out.append(" ") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    static func bytes(_ b: Int64) -> String {
        let kb = 1024.0, mb = kb * 1024, gb = mb * 1024, tb = gb * 1024
        let v = Double(b)
        if v >= tb { return String(format: "%.1f TB", v / tb) }
        if v >= gb { return String(format: "%.0f GB", v / gb) }
        if v >= mb { return String(format: "%.0f MB", v / mb) }
        return "\(b / 1024) KB"
    }

    /// The line under the calendar: the weight of the library.
    static func footer(diskBytes: Int64) -> String {
        diskBytes > 0 ? HomeStrings.onDisk.f(bytes(diskBytes)) : ""
    }

    /// "3 saves · Sep 25, 2026" or "nothing saved · …" — shown in the footer while hovering a day.
    static func hover(day: Date, saves: Int, locale: Locale = Localizer.shared.locale) -> String {
        let count = saves == 0 ? HomeStrings.nothingSaved.s
            : saves == 1 ? HomeStrings.saveOne.f(saves) : HomeStrings.saveMany.f(saves)
        let date = day.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
        return count + "  ·  " + date
    }
}

struct OverviewPanel: View {
    @Environment(AppModel.self) private var app
    @State private var hovered: HeatmapCell?
    @State private var headerHover = false

    private static let minContent: CGFloat = 560

    /// The panel takes two thirds of the width: across the full width a card stretches into a
    /// six-to-one strip and the whole block reads as having come apart.
    static func contentWidth(for width: CGFloat) -> CGFloat {
        width <= minContent ? width : max(minContent, width * 2 / 3)
    }

    var body: some View {
        let open = app.settings.overviewOpen
        VStack(alignment: .leading, spacing: 14) {
            header(open: open)
            if open {
                let stats = app.home.overviewStats
                OverviewColumn {
                    VStack(alignment: .leading, spacing: 20) {
                        cards(stats)
                        ActivityHeatmap(grid: app.home.heatmap, hovered: $hovered)
                        footer(stats)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(open: Bool) -> some View {
        Button {
            withAnimation(Theme.selectAnimation) { app.mutateSettings { $0.overviewOpen.toggle() } }
        } label: {
            HStack(spacing: 10) {
                IconView(icon: .chevronDown, size: 10, weight: .semibold)
                    .rotationEffect(.degrees(open ? 0 : -90))
                    .frame(width: 14)
                Text(HomeStrings.overview.s).font(Theme.fHead)
            }
            .foregroundStyle(headerHover ? Theme.text : (open ? Theme.text : Theme.textDim))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { headerHover = $0 }
        .accessibilityLabel(open ? HomeStrings.overviewCollapse.s : HomeStrings.overviewExpand.s)
    }

    private func cards(_ s: OverviewStats) -> some View {
        HStack(spacing: 8) {
            StatCard(label: HomeStrings.activeDays.s, value: OverviewFormat.number(s.activeDays))
            StatCard(label: HomeStrings.streak.s, value: OverviewFormat.days(s.streak))
            StatCard(label: HomeStrings.record.s, value: OverviewFormat.days(s.record))
            StatCard(label: HomeStrings.peakHour.s, value: OverviewFormat.hour(s.peakHour))
        }
    }

    private func footer(_ s: OverviewStats) -> some View {
        Text(hovered.map { OverviewFormat.hover(day: $0.day, saves: $0.saves) }
             ?? OverviewFormat.footer(diskBytes: s.diskBytes))
            .font(Theme.fLabel)
            .foregroundStyle(Theme.textDim)
            .frame(minHeight: 16, alignment: .leading)
            .lineLimit(1)
    }
}

/// Gives its child `OverviewPanel.contentWidth` of the proposed width (state-free, see `HeatmapFit`).
struct OverviewColumn: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? OverviewPanel.contentWidth(for: 800)
        let inner = subviews.first?.sizeThatFits(ProposedViewSize(width: OverviewPanel.contentWidth(for: width), height: nil)) ?? .zero
        return CGSize(width: width, height: inner.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: OverviewPanel.contentWidth(for: bounds.width), height: nil))
    }
}

/// A small grey caption over a large white number.
private struct StatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(Theme.fBadge).foregroundStyle(Theme.textDim).lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
