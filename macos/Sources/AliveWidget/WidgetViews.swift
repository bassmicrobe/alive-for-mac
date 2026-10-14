// Mac-only: the widget's three sizes. Colours are the app's Theme (Theme.swift) replicated as
// constants: the widget process does not link the UI module.
import AliveCore
import SwiftUI
import WidgetKit

enum WidgetPalette {
    static let bg = Color(hex: 0x1B1B1D)
    static let surface = Color(hex: 0x28282A)
    static let light = Color(hex: 0xCACACB)
    static let lightTop = Color(hex: 0xF2F2F4)
    static let text = Color(hex: 0xE9E9EB)
    static let textDim = Color(hex: 0x919196)
    static let secondary = Color(hex: 0xAEAEB3)
    static let hairline = Color(hex: 0x3A3A3D)
    static let green = Color(hex: 0x61E170)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

struct AliveWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AliveEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: SmallView(snapshot: snapshot, now: entry.date)
                case .systemMedium: MediumView(snapshot: snapshot, now: entry.date)
                default: LargeView(snapshot: snapshot, now: entry.date)
                }
            } else {
                NoDataView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - pieces

private struct Figure: View {
    let value: String
    let caption: String
    var size: CGFloat = 34
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ? WidgetPalette.lightTop : WidgetPalette.text)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(caption).font(.system(size: 11, weight: .medium)).foregroundStyle(WidgetPalette.textDim)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// Intensity 0...3 by the square root of the share of the busiest day (the app's own scale).
func widgetLevel(saves: Int, maxSaves: Int) -> Int? {
    guard saves > 0 else { return nil }
    return max(0, min(3, Int(3.999 * (Double(saves) / Double(max(1, maxSaves))).squareRoot())))
}

private struct Heatmap: View {
    let snapshot: WidgetSnapshot
    let now: Date
    var cell: CGFloat = 11
    var gap: CGFloat = 3

    private static let alpha: [Double] = [0x4C, 0x80, 0xB8, 0xF4].map { $0 / 255 }

    var body: some View {
        let columns = snapshot.heatmap(now: now)
        let maxSaves = columns.flatMap { $0 }.compactMap(\.saves).max() ?? 1
        HStack(alignment: .top, spacing: gap) {
            ForEach(columns.indices, id: \.self) { c in
                VStack(spacing: gap) {
                    ForEach(columns[c].indices, id: \.self) { r in
                        RoundedRectangle(cornerRadius: cell * 0.3, style: .continuous)
                            .fill(color(columns[c][r].saves, maxSaves))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ saves: Int?, _ maxSaves: Int) -> Color {
        guard let saves else { return .clear }
        guard let level = widgetLevel(saves: saves, maxSaves: maxSaves) else { return Color.white.opacity(Double(0x1A) / 255) }
        return WidgetPalette.light.opacity(Self.alpha[level])
    }
}

/// Fits the heatmap to the width it is given.
private struct FittedHeatmap: View {
    let snapshot: WidgetSnapshot
    let now: Date
    let gap: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let cols = CGFloat(WidgetSnapshot.heatmapWeeks)
            let cell = max(6, min(18, ((proxy.size.width - gap * (cols - 1)) / cols).rounded(.down)))
            Heatmap(snapshot: snapshot, now: now, cell: cell, gap: gap)
        }
        .aspectRatio(CGFloat(WidgetSnapshot.heatmapWeeks) / 7, contentMode: .fit)
    }
}

private func recentDate(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).day().locale(WidgetStrings.locale))
}

// MARK: - sizes

private struct SmallView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let streak = snapshot.streak(now: now)
        VStack(alignment: .leading, spacing: 0) {
            Figure(value: "\(streak)", caption: streak > 0 ? WidgetStrings.streakDays.s : WidgetStrings.noStreak.s,
                   size: 46, accent: streak > 0)
            Spacer(minLength: 6)
            Rectangle().fill(WidgetPalette.hairline).frame(height: 1)
            Spacer(minLength: 8)
            Figure(value: "\(snapshot.savesToday(now: now))", caption: WidgetStrings.savesToday.s, size: 26)
        }
        .padding(16)
    }
}

private struct MediumView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let streak = snapshot.streak(now: now)
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Figure(value: "\(streak)", caption: streak > 0 ? WidgetStrings.streakDays.s : WidgetStrings.noStreak.s,
                       size: 40, accent: streak > 0)
                Figure(value: "\(snapshot.activeDays)", caption: WidgetStrings.activeDays.s, size: 22)
            }
            .frame(width: 96, alignment: .leading)
            FittedHeatmap(snapshot: snapshot, now: now)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }
}

private struct LargeView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let streak = snapshot.streak(now: now)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 22) {
                Figure(value: "\(streak)", caption: streak > 0 ? WidgetStrings.streakDays.s : WidgetStrings.noStreak.s,
                       size: 38, accent: streak > 0)
                Figure(value: "\(snapshot.savesToday(now: now))", caption: WidgetStrings.savesToday.s, size: 26)
                Figure(value: "\(snapshot.activeDays)", caption: WidgetStrings.activeDays.s, size: 26)
            }
            FittedHeatmap(snapshot: snapshot, now: now)
            Rectangle().fill(WidgetPalette.hairline).frame(height: 1)
            Text(WidgetStrings.recentProjects.s.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(WidgetPalette.textDim)
            VStack(spacing: 7) {
                if snapshot.recent.isEmpty {
                    Text(WidgetStrings.noRecent.s).font(.system(size: 12)).foregroundStyle(WidgetPalette.textDim)
                }
                ForEach(Array(snapshot.recent.prefix(WidgetSnapshot.recentCount).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Text(item.name).font(.system(size: 13, weight: .medium)).foregroundStyle(WidgetPalette.text)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 6)
                        Text(recentDate(item.modified)).font(.system(size: 12)).monospacedDigit()
                            .foregroundStyle(WidgetPalette.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

/// The placeholder before the app has ever written a snapshot.
struct NoDataView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "waveform").font(.system(size: 20, weight: .semibold)).foregroundStyle(WidgetPalette.light)
            Spacer(minLength: 4)
            Text(WidgetStrings.noData.s).font(.system(size: 14, weight: .semibold)).foregroundStyle(WidgetPalette.text)
            Text(WidgetStrings.noDataHint.s).font(.system(size: 11)).foregroundStyle(WidgetPalette.textDim)
        }
        .padding(16)
    }
}
