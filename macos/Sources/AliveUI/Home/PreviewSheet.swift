// Port of src/PreviewDialog.cs (PreviewDialog + ArrangementView): the whole arrangement large —
// tracks, their colours and clips on a ruler — with zoom and scroll added for the Mac.
import AliveCore
import SwiftUI

/// Sizes of the preview picture. Pure so the limits can be tested.
enum PreviewSizing {
    static let zoomSteps = [1, 2, 4, 8, 16, 32]
    /// A picture is never wider than this many pixels (a bitmap of many megabytes is not a preview).
    static let maxPixelWidth = 16_000
    static let maxPixels = 48_000_000
    /// Point height per track when "taller tracks" is on.
    static let tallLane = 14.0

    struct Plan: Equatable {
        /// Size of the picture on screen, in points.
        var points: CGSize
        /// Pixels per point of the bitmap (2 on a retina screen while it fits).
        var scale: Double
        var pixelWidth: Int { Int((points.width * scale).rounded()) }
        var pixelHeight: Int { Int((points.height * scale).rounded()) }
    }

    static func plan(view: CGSize, zoomIndex: Int, trackCount: Int, taller: Bool, backingScale: Double) -> Plan {
        let zoom = zoomSteps[min(max(zoomIndex, 0), zoomSteps.count - 1)]
        let width = max(80, view.width) * Double(zoom)
        var height = max(80, view.height)
        if taller {
            let options = RenderOptions.preview(scale: 1, minLane: tallLane)
            height = max(height, Double(ArrangementRender.fullHeight(trackCount: trackCount, options: options)) + 24)
        }
        var scale = max(1, backingScale)
        while scale > 1, width * scale > Double(maxPixelWidth) || width * scale * height * scale > Double(maxPixels) {
            scale -= 1
        }
        // Even at 1x a very wide picture is cut down instead of allocating gigabytes.
        let cappedWidth = min(width, Double(maxPixelWidth))
        return Plan(points: CGSize(width: cappedWidth, height: height), scale: scale)
    }

    /// The header line: folder, tempo, key and the size of the arrangement.
    static func subtitle(directory: String, key: String, arrangement a: Arrangement?) -> String {
        let sep = "   ·   "
        guard let a else { return directory + sep + HomeStrings.previewReading.s }
        if let error = a.error { return directory + sep + error }
        var parts = [directory]
        if a.tempo > 0 { parts.append(HomeStrings.previewBPM.f(tempoText(a.tempo))) }
        if !key.isEmpty, a.tempo > 0 { parts.append(key) }
        parts.append(HomeStrings.previewBars.f(a.bars))
        parts.append(HomeStrings.previewTracks.f(a.tracks.count))
        parts.append(HomeStrings.previewClips.f(a.clipCount))
        return parts.joined(separator: sep)
    }

    /// "150", "127.5", "127.35" — upstream's `0.##`.
    static func tempoText(_ bpm: Double) -> String {
        var s = String(format: "%.2f", bpm)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

struct PreviewSheet: View {
    let path: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var arrangement: Arrangement?
    @State private var viewSize: CGSize = .zero
    @State private var zoomIndex = 0
    @State private var taller = false
    @State private var picture: PicturePlan?
    /// Looked up once per catalog revision, not on every body evaluation.
    @State private var entry: SetEntry?

    private struct PicturePlan {
        var image: CGImage
        var plan: PreviewSizing.Plan
    }

    private struct RenderKey: Hashable {
        var loaded: Bool
        var width: Int
        var height: Int
        var zoom: Int
        var taller: Bool
        var scale: Double
    }

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
        .task { arrangement = await app.home.previewLoader.load(path) }
        .task(id: renderKey) { await render() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.fDialogTitle).foregroundStyle(Theme.text).lineLimit(1)
                Text(PreviewSizing.subtitle(directory: directory, key: entry?.key ?? "", arrangement: arrangement))
                    .font(Theme.fSmall).foregroundStyle(Theme.textDim).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if arrangement?.hasContent == true { zoomControls }
            CircleIconButton(icon: .close, help: CommonStrings.close.s) { dismiss() }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            CircleIconButton(icon: .viewList, help: HomeStrings.tallerTracks.s, isActive: taller) { taller.toggle() }
            Text(HomeStrings.zoomLevel.f(PreviewSizing.zoomSteps[zoomIndex]))
                .font(Theme.fLabel).foregroundStyle(Theme.textDim).monospacedDigit().frame(width: 36)
            CircleIconButton(icon: .minimize, help: HomeStrings.zoomOut.s) { zoom(by: -1) }
                .disabled(zoomIndex == 0)
            CircleIconButton(icon: .plus, help: HomeStrings.zoomIn.s) { zoom(by: +1) }
                .disabled(zoomIndex == PreviewSizing.zoomSteps.count - 1)
            PillButton(title: HomeStrings.zoomFit.s) { zoomIndex = 0; taller = false }
                .disabled(zoomIndex == 0 && !taller)
        }
    }

    private func zoom(by delta: Int) {
        zoomIndex = min(max(zoomIndex + delta, 0), PreviewSizing.zoomSteps.count - 1)
    }

    /// Esc and ⌘Y close (upstream toggled the preview with the key that opened it), + / - zoom, 0 fits.
    private var shortcuts: some View {
        ZStack {
            Button("") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("") { dismiss() }.keyboardShortcut("y", modifiers: .command)
            Button("") { zoom(by: +1) }.keyboardShortcut("+", modifiers: [])
            Button("") { zoom(by: +1) }.keyboardShortcut("=", modifiers: [])
            Button("") { zoom(by: -1) }.keyboardShortcut("-", modifiers: [])
            Button("") { zoomIndex = 0 }.keyboardShortcut("0", modifiers: [])
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
        .background(GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size, initial: true) { _, size in viewSize = size }
        })
    }

    @ViewBuilder private var content: some View {
        if let a = arrangement {
            if let error = a.error, !a.hasContent {
                hint(error)
            } else if !a.hasContent {
                hint(HomeStrings.previewEmpty.s)
            } else if let picture {
                ScrollView([.horizontal, .vertical]) {
                    Image(decorative: picture.image, scale: picture.plan.scale)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: picture.plan.points.width, height: picture.plan.points.height)
                        .padding(12)
                }
                .scrollIndicators(.visible)
                .gesture(MagnifyGesture().onEnded { value in
                    if value.magnification > 1.2 { zoom(by: +1) } else if value.magnification < 0.83 { zoom(by: -1) }
                })
            }
        } else {
            hint(HomeStrings.previewReading.s)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(Theme.fBody).foregroundStyle(Theme.textDim)
    }

    // MARK: - Rendering

    private var plan: PreviewSizing.Plan {
        PreviewSizing.plan(view: viewInset, zoomIndex: zoomIndex, trackCount: arrangement?.tracks.count ?? 0,
                           taller: taller, backingScale: displayScale)
    }

    /// The picture keeps a margin inside the card, like upstream's 12 px.
    private var viewInset: CGSize {
        CGSize(width: max(0, viewSize.width - 24), height: max(0, viewSize.height - 24))
    }

    private var renderKey: RenderKey {
        let p = plan
        return RenderKey(loaded: arrangement?.hasContent == true, width: p.pixelWidth, height: p.pixelHeight,
                         zoom: zoomIndex, taller: taller, scale: p.scale)
    }

    private func render() async {
        guard let a = arrangement, a.hasContent, viewSize.width > 100 else { return }
        let plan = plan
        // Debounced: a window being resized asks for a new size at every frame.
        try? await Task.sleep(nanoseconds: 120_000_000)
        if Task.isCancelled { return }
        let options = RenderOptions.preview(scale: plan.scale, minLane: taller ? PreviewSizing.tallLane : 2)
        let (w, h) = (plan.pixelWidth, plan.pixelHeight)
        let image = await Task.detached(priority: .userInitiated) {
            ArrangementRender.makeImage(a, width: w, height: h, options: options)
        }.value
        if Task.isCancelled { return }
        guard let image else { return }
        picture = PicturePlan(image: image, plan: plan)
    }
}
