// Mac-only: the pieces of the Samples panel — heading, rows, links, the usage chart and the wave.
import SwiftUI
import AliveCore

struct PanelHeader: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(Theme.fHead)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Text(trailing)
                .font(Theme.fBody)
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// "Samples:   612". A nil value says `empty` in the quiet colour ("none", "never").
struct PanelRow: View {
    let label: String
    let value: String?
    var empty = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 8)
            Text(value ?? empty)
                .font(Theme.fBody)
                .foregroundStyle(value == nil ? Theme.secondaryText : Theme.text)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// A path that shows itself in Finder when clicked.
struct PathLink: View {
    let model: SamplesModel
    let path: String
    @State private var hovering = false

    var body: some View {
        Button {
            model.app.revealInFinder(path: path)
        } label: {
            Text(path)
                .font(Theme.fBody)
                .foregroundStyle(hovering ? Theme.text : Theme.secondaryText)
                .underline(hovering)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .help(CommonStrings.showInFinder.s)
    }
}

// MARK: - Link lists

/// A heading and a column of rows that lead somewhere; `shown` of `total` are at hand.
struct LinkList<Rows: View>: View {
    let heading: String
    let total: Int
    let shown: Int
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading).font(Theme.fLabel).foregroundStyle(Theme.secondaryText).padding(.bottom, 4)
            rows()
            if total > shown {
                Text(SamplesStrings.panelMore.f(SampleFormat.number(total - shown)))
                    .font(Theme.fLabel)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 2)
            }
        }
    }
}

struct LinkRow: View {
    let text: String
    let note: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text)
                    .font(Theme.fBody)
                    .foregroundStyle(hovering ? Color.white : Theme.text)
                    .underline(hovering)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(note).font(Theme.fBody).foregroundStyle(Theme.secondaryText).monospacedDigit()
            }
            .frame(minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
    }
}

/// The projects that use it — one line per project, under its newest version; a click selects that
/// set on the Sets tab.
struct ProjectsList: View {
    let model: SamplesModel
    let sets: [SetEntry]
    private static let cap = 30

    var body: some View {
        if !sets.isEmpty {
            LinkList(heading: SamplesStrings.panelProjectsList.f(sets.count), total: sets.count,
                     shown: min(sets.count, Self.cap)) {
                ForEach(sets.prefix(Self.cap), id: \.path) { s in
                    LinkRow(text: s.projectName.isEmpty ? s.name : s.projectName, note: "") { open(s) }
                }
            }
        }
    }

    private func open(_ s: SetEntry) {
        model.app.searchText = ""
        model.app.sets.select(path: s.path)
        model.app.tab = .sets
    }
}

// MARK: - Usage by month

/// Projects that saved a set using it, month by month: an axis of two dates and the tallest count.
struct UsageChart: View {
    let months: SampleMonths
    private static let height: CGFloat = 48

    var body: some View {
        if !months.counts.isEmpty {
            let top = max(1, months.counts.max() ?? 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(SamplesStrings.panelByMonth.s).font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
                bars(top: top)
                HStack {
                    Text(label(0)).font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text(label(months.counts.count - 1)).font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private func bars(top: Int) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(months.counts.indices, id: \.self) { i in
                let n = months.counts[i]
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(n > 0 ? Theme.secondaryText : Theme.hairline)
                    .frame(height: n > 0 ? max(4, Self.height * CGFloat(n) / CGFloat(top)) : 2)
                    .frame(maxWidth: .infinity)
                    .help("\(label(i)) · \(n)")
            }
        }
        .frame(height: Self.height, alignment: .bottom)
        .overlay(alignment: .topLeading) {
            Text(SampleFormat.number(top)).font(Theme.fMini).foregroundStyle(Theme.secondaryText).offset(y: -12)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SamplesStrings.panelByMonth.s)
    }

    /// "2026-09" for the month at position `i`.
    private func label(_ i: Int) -> String {
        let d = Calendar.current.date(byAdding: .month, value: i, to: months.from) ?? months.from
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f.string(from: d)
    }
}

// MARK: - Wave

/// The picture of the sample; a click plays from there. Progress follows the shared player.
struct WaveView: View {
    let model: SamplesModel
    let file: SampleFile
    let path: String
    private static let height: CGFloat = 84

    var body: some View {
        let info = model.info?.path == path ? model.info : nil
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.sunken)
            content(info?.wave ?? .reading)
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in
            guard file.canPreview, let w = geometryWidth, w > 0 else { return }
            model.seek(toFraction: min(1, max(0, tap.location.x / w)))
        })
        .background(GeometryReader { g in Color.clear.preference(key: WaveWidthKey.self, value: g.size.width) })
        .onPreferenceChange(WaveWidthKey.self) { geometryWidth = $0 }
        .help(file.canPreview ? SamplesStrings.play.s : SamplesStrings.notPlayable.s)
        .modifier(KeyboardScrub(value: progress ?? 0, isEnabled: file.canPreview && progress != nil) {
            model.seek(toFraction: $0)
        })
        .accessibilityElement()
        .accessibilityLabel(SamplesStrings.waveSeek.s)
        .accessibilityValue(progress.map { "\(Int($0 * 100))%" } ?? "")
        .accessibilityAdjustableAction { direction in
            guard file.canPreview, let p = progress else { return }
            switch direction {
            case .increment: model.seek(toFraction: min(1, p + KeyboardScrub.step))
            case .decrement: model.seek(toFraction: max(0, p - KeyboardScrub.step))
            @unknown default: break
            }
        }
    }

    @State private var geometryWidth: CGFloat?

    @ViewBuilder private func content(_ wave: SampleInfo.Wave) -> some View {
        if !file.canPreview {
            hint(SamplesStrings.waveOnlyLive.s)
        } else {
            switch wave {
            case .reading: hint(SamplesStrings.waveReading.s)
            case .unavailable: hint(SamplesStrings.waveNone.s)
            case .peaks(let peaks): WaveCanvas(peaks: peaks, progress: progress)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
    }

    private var progress: Double? {
        guard model.isPlaying(path), model.audio.duration > 0 else { return nil }
        return min(1, model.audio.currentTime / model.audio.duration)
    }
}

private struct WaveWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct WaveCanvas: View {
    let peaks: [Float]
    let progress: Double?

    var body: some View {
        Canvas { ctx, size in
            guard !peaks.isEmpty else { return }
            let mid = size.height / 2
            let step = size.width / CGFloat(peaks.count)
            let barW = max(1, step - 1)
            for (i, p) in peaks.enumerated() {
                let h = max(1.5, CGFloat(p) * (size.height - 8))
                let rect = CGRect(x: CGFloat(i) * step, y: mid - h / 2, width: barW, height: h)
                let played = progress.map { Double(i) / Double(peaks.count) <= $0 } ?? false
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(1.5, barW / 2)),
                         with: .color(played ? Theme.green : Theme.light.opacity(0.75)))
            }
        }
        .padding(.horizontal, 6)
        .accessibilityHidden(true)
    }
}
