// Port of src/PreviewDialog.cs (PreviewDialog): the whole arrangement large — tracks, their colours
// and clips on a ruler — moved about as Live's arrangement is (upstream a6c8dc1). The canvas and its
// navigation are `ArrangementCanvasView`; this file is the sheet around it and the caption.
import AliveCore
import AliveRender
import SwiftUI

/// Texts of the preview. Pure so they can be tested.
enum PreviewSizing {
    /// The metrics line under the path: tempo, key and the size of the arrangement. Never contains
    /// the path (that has its own line), so nothing can push these out through truncation.
    static func metrics(path: String, key: String, arrangement a: Arrangement?) -> String {
        let sep = "   ·   "
        guard let a else { return HomeStrings.previewReading.s }
        if let error = a.error { return ReadErrorLog.note(error, of: path) }
        var parts: [String] = []
        if a.tempo > 0 { parts.append(HomeStrings.previewBPM.f(tempoText(a.tempo))) }
        if !key.isEmpty, a.tempo > 0 { parts.append(key) }
        // Bars in the set's own time signature (`Arrangement.bars`), the singular with a form of its own.
        parts.append(count(a.bars, one: .bar1, many: .previewBars))
        parts.append(count(a.tracks.count, one: .track1, many: .previewTracks))
        parts.append(count(a.clipCount, one: .clip1, many: .previewClips))
        return parts.joined(separator: sep)
    }

    /// "1 bar", "2 bars" (upstream 9ce4b4b `Chrome.Plural`).
    private static func count(_ n: Int, one: PreviewNavStrings, many: HomeStrings) -> String {
        n == 1 ? one.f(n) : many.f(n)
    }

    /// "150", "127.5", "127.35" — upstream's `0.##`, the same in every system language.
    static func tempoText(_ bpm: Double) -> String {
        var s = String(format: "%.2f", bpm)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// The zoom label: "1×" for the whole song across, "2.5×" zoomed in.
    static func zoomText(_ zoom: Double) -> String {
        var s = String(format: "%.1f", zoom)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return PreviewNavStrings.zoomValue.f(s)
    }
}

struct PreviewSheet: View {
    let path: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var arrangement: Arrangement?
    @State private var control = PreviewCanvasControl()
    /// Looked up once per catalog revision, not on every body evaluation.
    @State private var entry: SetEntry?

    private var title: String { entry?.name ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    private var directory: String { entry?.directory ?? (path as NSString).deletingLastPathComponent }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            canvas
        }
        .padding(Theme.pad)
        .frame(minWidth: 720, idealWidth: 1100, maxWidth: .infinity,
               minHeight: 460, idealHeight: 680, maxHeight: .infinity)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .background(shortcuts)
        .task(id: app.catalog.revision) { entry = app.catalog.sets.first { $0.path == path } }
        // Another set never shows the last one's picture while it is read (upstream 9ce4b4b).
        .task(id: path) {
            arrangement = nil
            arrangement = await app.home.previewLoader.load(path)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.fDialogTitle).foregroundStyle(Theme.text).lineLimit(1)
                Text(directory)
                    .font(Theme.fSmall).foregroundStyle(Theme.secondaryText).lineLimit(1).truncationMode(.middle)
                    .help(directory)
                Text(PreviewSizing.metrics(path: path, key: entry?.key ?? "", arrangement: arrangement))
                    .font(Theme.fSmall).foregroundStyle(Theme.secondaryText).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if arrangement?.hasContent == true { zoomControls }
            CircleIconButton(icon: .close, help: CommonStrings.close.s) { dismiss() }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            Text(PreviewSizing.zoomText(control.zoom))
                .font(Theme.fLabel).foregroundStyle(Theme.secondaryText).monospacedDigit().frame(minWidth: 36)
            CircleIconButton(icon: .minimize, help: HomeStrings.zoomOut.s) { control.zoomOut() }
                .disabled(control.zoom <= 1.001)
            CircleIconButton(icon: .plus, help: HomeStrings.zoomIn.s) { control.zoomIn() }
                .disabled(control.zoom >= control.maxZoom - 0.001)
            PillButton(title: HomeStrings.zoomFit.s) { control.fit() }
                .disabled(control.isAtFit)
        }
        .help(PreviewNavStrings.navigationHelp.s)
    }

    /// Esc and ⌘Y close (upstream toggled the preview with the key that opened it), + / - zoom, 0 fits.
    private var shortcuts: some View {
        ZStack {
            Button("") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("") { dismiss() }.keyboardShortcut("y", modifiers: .command)
            Button("") { control.zoomIn() }.keyboardShortcut("+", modifiers: [])
            Button("") { control.zoomIn() }.keyboardShortcut("=", modifiers: [])
            Button("") { control.zoomOut() }.keyboardShortcut("-", modifiers: [])
            Button("") { control.fit() }.keyboardShortcut("0", modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // MARK: - Canvas

    private var canvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous).fill(Theme.surface)
            content
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        if let a = arrangement {
            if let error = a.error, !a.hasContent {
                hint(ReadErrorLog.note(error, of: path))
            } else if !a.hasContent {
                hint(HomeStrings.previewEmpty.s)
            } else {
                PreviewCanvas(path: path, arrangement: a, control: control)
            }
        } else {
            hint(HomeStrings.previewReading.s)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(Theme.fBody).foregroundStyle(Theme.secondaryText)
    }
}
