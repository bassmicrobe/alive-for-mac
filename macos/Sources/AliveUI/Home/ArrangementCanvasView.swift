// Port of the ArrangementView half of src/PreviewDialog.cs (upstream a6c8dc1): the canvas of the
// full-screen preview, moved about as Live's arrangement is. The state and the maths are
// `ArrangementViewport` (AliveRender); this view turns events into calls and keeps the picture.
import AliveCore
import AliveRender
import AppKit
import SwiftUI

/// The header's remote control of the canvas, and what the canvas reports back: the zoom for the
/// label and whether anything differs from the fitted view.
@MainActor
@Observable
final class PreviewCanvasControl {
    /// 1 = the whole song across.
    private(set) var zoom = 1.0
    private(set) var maxZoom = 1.0
    private(set) var isAtFit = true

    @ObservationIgnored weak var canvas: ArrangementCanvasView?

    func zoomIn() { canvas?.zoom(factor: 2) }
    func zoomOut() { canvas?.zoom(factor: 0.5) }
    func fit() { canvas?.resetView() }

    /// Called by the canvas after a move; only a change reaches the observers.
    func publish(zoom: Double, maxZoom: Double, isAtFit: Bool) {
        if self.zoom != zoom { self.zoom = zoom }
        if self.maxZoom != maxZoom { self.maxZoom = maxZoom }
        if self.isAtFit != isAtFit { self.isAtFit = isAtFit }
    }
}

struct PreviewCanvas: NSViewRepresentable {
    let path: String
    let arrangement: Arrangement
    let control: PreviewCanvasControl

    func makeNSView(context: Context) -> ArrangementCanvasView {
        let view = ArrangementCanvasView()
        view.control = control
        control.canvas = view
        return view
    }

    func updateNSView(_ view: ArrangementCanvasView, context: Context) {
        view.show(arrangement, path: path)
    }
}

/// y-down, like the renderer's own arithmetic. Everything is counted in pixels (`backingScale`
/// per point) so the picture is sharp on a Retina screen.
final class ArrangementCanvasView: NSView {
    /// The margin inside the card, like upstream's 12 px.
    static let pad: CGFloat = 12

    weak var control: PreviewCanvasControl?
    private var arrangement: Arrangement?
    private var shownPath: String?
    private var viewport = ArrangementViewport()
    private var wantedNameW = 0

    private struct BodyKey: Equatable {
        var width: Int, height: Int
        var viewport: ArrangementViewport
        var scale: Double
    }
    /// The clips and the grid as last drawn, kept while the view stands still: a fading scrollbar
    /// repaints dozens of times a second and must not draw tens of thousands of notes each time.
    private var body: (key: BodyKey, image: CGImage)?

    private var panFrom: CGPoint?
    private var panStart = (x: 0.0, y: 0.0)
    private var scrollerAlpha: CGFloat = 0
    private var lastScrollerPing = 0.0
    private var fadeTimer: Timer?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.image)
        setAccessibilityLabel(HomeStrings.previewTitle.s)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Content

    /// The set to show. Another set starts from the fitted view and never keeps the old picture.
    func show(_ a: Arrangement, path: String) {
        guard shownPath != path else { return }
        shownPath = path
        arrangement = a
        viewport = ArrangementViewport()
        body = nil
        wantedNameW = ArrangementRender.nameColumnWidth(a.tracks, options)
        needsDisplay = true
        if let space = makeSpace() { publish(space) }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        body = nil
        if let a = arrangement { wantedNameW = ArrangementRender.nameColumnWidth(a.tracks, options) }
        needsDisplay = true
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    private var options: RenderOptions { .preview(scale: Double(backingScale)) }

    /// The drawing area in pixels, inside the margin; nil while there is no room.
    private func makeSpace() -> ArrangementSpace? {
        guard let a = arrangement else { return nil }
        let b = backingScale
        let w = Int(((bounds.width - Self.pad * 2) * b).rounded(.down))
        let h = Int(((bounds.height - Self.pad * 2) * b).rounded(.down))
        guard w > 0, h > 0 else { return nil }
        return ArrangementSpace(area: CGRect(x: 0, y: 0, width: w, height: h), arrangement: a,
                                options: options, wantedNameW: wantedNameW)
    }

    // MARK: - Moves

    private func edit(_ change: (inout ArrangementViewport, ArrangementSpace) -> Void) {
        guard let space = makeSpace() else { return }
        change(&viewport, space)
        needsDisplay = true
        pingScrollers()
        publish(space)
    }

    func zoom(factor: Double) { edit { $0.zoom(factor: factor, atX: $1.plot.midX, in: $1) } }

    func resetView() { edit { v, s in v.reset(); v.ensure(in: s) } }

    private func publish(_ space: ArrangementSpace) {
        var current = viewport
        current.ensure(in: space)
        var fresh = ArrangementViewport()
        fresh.ensure(in: space)
        control?.publish(zoom: current.zoomFactor(in: space), maxZoom: current.maxZoomFactor(in: space), isAtFit: current == fresh)
    }

    /// A point of the view in the drawing area's pixels.
    private func pixelPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let b = backingScale
        return CGPoint(x: (p.x - Self.pad) * b, y: (p.y - Self.pad) * b)
    }

    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags
        let input = ArrangementScroll(dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY),
                                      precise: event.hasPreciseScrollingDeltas,
                                      shift: flags.contains(.shift), command: flags.contains(.command),
                                      option: flags.contains(.option))
        let at = pixelPoint(event)
        edit { $0.apply(input, at: at, in: $1) }
    }

    /// A pinch zooms the time around the fingers.
    override func magnify(with event: NSEvent) {
        let at = pixelPoint(event)
        edit { $0.zoom(factor: max(0.1, 1 + Double(event.magnification)), atX: at.x, in: $1) }
    }

    // The middle button drags both ways at once.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, makeSpace() != nil else { return super.otherMouseDown(with: event) }
        panFrom = pixelPoint(event)
        panStart = (viewport.scrollX, viewport.scrollY)
        NSCursor.closedHand.push()
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard let from = panFrom else { return super.otherMouseDragged(with: event) }
        let now = pixelPoint(event)
        let start = panStart
        // The arrangement goes with the hand.
        edit { $0.scroll(toX: start.x - Double(now.x - from.x), y: start.y - Double(now.y - from.y), in: $1) }
    }

    override func otherMouseUp(with event: NSEvent) {
        guard panFrom != nil else { return super.otherMouseUp(with: event) }
        panFrom = nil
        NSCursor.pop()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let a = arrangement, let ctx = NSGraphicsContext.current?.cgContext, let space = makeSpace() else { return }
        viewport.ensure(in: space)
        let area = space.area
        let b = backingScale
        ctx.saveGState()
        ctx.scaleBy(x: 1 / b, y: 1 / b)
        ctx.translateBy(x: Self.pad * b, y: Self.pad * b)
        if let image = bodyImage(a, space) {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: area.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: area.size))
            ctx.restoreGState()
        }
        // The names and the bar numbers straight onto the screen, apart from the cached layer.
        ArrangementRender.drawViewText(ctx, area: area, arrangement: a, options: space.options,
                                       view: viewport, wantedNameW: wantedNameW)
        paintScrollers(ctx, space)
        ctx.restoreGState()
    }

    private func bodyImage(_ a: Arrangement, _ space: ArrangementSpace) -> CGImage? {
        let key = BodyKey(width: Int(space.area.width), height: Int(space.area.height), viewport: viewport,
                          scale: space.options.scale)
        if let body, body.key == key { return body.image }
        guard let image = ArrangementRender.makeViewImage(a, size: space.area.size, options: space.options,
                                                          view: viewport, wantedNameW: wantedNameW) else { return nil }
        body = (key, image)
        return image
    }

    // MARK: - Scrollers

    /// Thin bars that show where the view stands, and fade away when it stops moving.
    private func paintScrollers(_ g: CGContext, _ space: ArrangementSpace) {
        guard scrollerAlpha > 0.01 else { return }
        let k = CGFloat(space.options.scale)
        let plot = space.plot
        g.setFillColor(CGColor(gray: 1, alpha: 0.38 * scrollerAlpha))
        let total = CGFloat(ArrangementRender.lanesHeight(trackCount: space.trackCount, laneH: viewport.laneH, options: space.options))
        if total > plot.height {
            let track = plot.height - 4 * k
            let h = max(40 * k, track * plot.height / total)
            let y = plot.minY + 2 * k + (track - h) * CGFloat(viewport.scrollY) / max(1, total - plot.height)
            fillBar(g, CGRect(x: space.area.maxX - 6 * k, y: y, width: 4 * k, height: h))
        }
        let width = CGFloat(space.end * viewport.pxPerBeat)
        if width > plot.width + 0.5 {
            let track = plot.width - 4 * k
            let w = max(40 * k, track * plot.width / width)
            let x = plot.minX + 2 * k + (track - w) * CGFloat(viewport.scrollX) / max(1, width - plot.width)
            fillBar(g, CGRect(x: x, y: space.area.maxY - 6 * k, width: w, height: 4 * k))
        }
    }

    private func fillBar(_ g: CGContext, _ r: CGRect) {
        let radius = min(r.width, r.height) / 2
        g.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        g.fillPath()
    }

    private func pingScrollers() {
        scrollerAlpha = 1
        lastScrollerPing = CACurrentMediaTime()
        guard fadeTimer == nil else { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.fadeScrollers(timer)
            }
        }
    }

    private func fadeScrollers(_ timer: Timer) {
        let idle = CACurrentMediaTime() - lastScrollerPing
        scrollerAlpha = idle < 0.9 ? 1 : max(0, 1 - CGFloat(idle - 0.9) / 0.4)
        needsDisplay = true
        if scrollerAlpha == 0 {
            timer.invalidate()
            fadeTimer = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window == nil else { return }
        fadeTimer?.invalidate()
        fadeTimer = nil
    }
}
