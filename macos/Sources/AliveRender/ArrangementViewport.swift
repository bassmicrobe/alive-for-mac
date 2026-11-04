// Port of the view state of ArrangementView in src/PreviewDialog.cs (upstream a6c8dc1): how the
// full-screen preview is moved about as Live's arrangement is. Pure and in pixels, so the whole
// navigation is tested without a window; the NSView in AliveUI only turns events into calls.
import AliveCore
import CoreGraphics
import Foundation

/// What the viewport measures against: the drawing area, the arrangement's size and the options.
public struct ArrangementSpace: Sendable {
    /// The area the arrangement is drawn in, in pixels.
    public var area: CGRect
    public var trackCount: Int
    /// The length shown: the last beat with anything on it, but at least one bar.
    public var end: Double
    public var options: RenderOptions
    /// Pixels the longest track name needs (`ArrangementRender.nameColumnWidth`).
    public var wantedNameW: Int

    public init(area: CGRect, trackCount: Int, end: Double, options: RenderOptions, wantedNameW: Int = 0) {
        self.area = area; self.trackCount = trackCount; self.end = max(end, 4)
        self.options = options; self.wantedNameW = wantedNameW
    }

    public init(area: CGRect, arrangement a: Arrangement, options: RenderOptions, wantedNameW: Int = 0) {
        self.init(area: area, trackCount: a.tracks.count, end: a.end, options: options, wantedNameW: wantedNameW)
    }

    /// Where the tracks go: the area less the name column and the ruler.
    public var plot: CGRect { ArrangementRender.plot(area: area, options: options, wantedNameW: wantedNameW) }
}

/// One turn of a scroll wheel or trackpad, with the keys held.
public struct ArrangementScroll: Sendable {
    /// AppKit's `scrollingDeltaX/Y`: positive moves the content right / down.
    public var dx: Double, dy: Double
    /// A trackpad (deltas in points that the content follows one to one) rather than a wheel
    /// (deltas in notches).
    public var precise: Bool
    public var shift = false, command = false, option = false

    public init(dx: Double, dy: Double, precise: Bool, shift: Bool = false, command: Bool = false, option: Bool = false) {
        self.dx = dx; self.dy = dy; self.precise = precise
        self.shift = shift; self.command = command; self.option = option
    }
}

/// The arrangement view, scrolled and zoomed: the wheel scrolls the tracks, Shift+wheel the time,
/// ⌘+wheel zooms the time around the cursor, ⌥+wheel makes the tracks taller or lower, and the
/// middle button drags both ways at once (Ctrl and Alt on Windows). A track is never lower than
/// its name: with many of them the tracks scroll rather than squeeze the names into one another.
/// A few fill the height.
public struct ArrangementViewport: Equatable, Sendable {
    /// Pixels per beat. Zero until the first `ensure`, which fits the whole song across.
    public private(set) var pxPerBeat = 0.0
    public private(set) var scrollX = 0.0
    public private(set) var scrollY = 0.0
    /// Pixels per track. Zero until the first `ensure`.
    public private(set) var laneH = 0
    /// The track height is the fitted one (not set by hand): it follows a resize.
    public private(set) var lanesFitted = true
    /// The whole song across: kept through a resize until a zoom.
    public private(set) var fitted = true

    public init() {}

    // Per notch of the wheel, in points (upstream's numbers).
    static let notchTime = 90.0, notchTracks = 60.0, notchLane = 6.0
    static let zoomPerNotch = 1.25
    /// A trackpad moves a notch in this many points of delta.
    static let trackpadNotch = 20.0
    static let maxBeatWidth = 160.0, maxLaneHeight = 160.0

    // MARK: measures

    private func fitPx(_ s: ArrangementSpace) -> Double { Double(s.plot.width) / s.end }
    private func maxPx(_ s: ArrangementSpace) -> Double { Self.maxBeatWidth * s.options.scale }
    private func minLane(_ s: ArrangementSpace) -> Int { ArrangementRender.minViewLane(s.options) }
    private func maxLane(_ s: ArrangementSpace) -> Int { Int((Self.maxLaneHeight * s.options.scale).rounded()) }
    private func contentW(_ s: ArrangementSpace) -> Double { s.end * pxPerBeat }
    private func contentH(_ s: ArrangementSpace) -> Int {
        ArrangementRender.lanesHeight(trackCount: s.trackCount, laneH: laneH, options: s.options)
    }

    /// As tall as fits, but never lower than a name.
    private func defaultLane(_ s: ArrangementSpace) -> Int {
        let n = max(1, s.trackCount)
        let gap = ArrangementRender.px(s.options, 2)
        let fit = (Int(s.plot.height) - gap * (n - 1)) / n
        return max(minLane(s), min(ArrangementRender.px(s.options, s.options.maxLane), fit))
    }

    /// 1 for the whole song across; larger zoomed in.
    public func zoomFactor(in s: ArrangementSpace) -> Double {
        let fit = fitPx(s)
        return fit > 0 && pxPerBeat > 0 ? pxPerBeat / fit : 1
    }

    public func maxZoomFactor(in s: ArrangementSpace) -> Double {
        let fit = fitPx(s)
        return fit > 0 ? max(1, maxPx(s) / fit) : 1
    }

    // MARK: state

    /// Fits the song across and the tracks down on first use and after a resize, then keeps the
    /// scroll inside the content.
    public mutating func ensure(in s: ArrangementSpace) {
        guard s.trackCount > 0 else { return }
        if pxPerBeat <= 0 || fitted { pxPerBeat = fitPx(s) }
        if laneH <= 0 || lanesFitted { laneH = defaultLane(s) }
        clamp(in: s)
    }

    /// Back to the whole song, the fitted track height and the top left.
    public mutating func reset() { self = ArrangementViewport() }

    public mutating func clamp(in s: ArrangementSpace) {
        let plot = s.plot
        scrollX = max(0, min(contentW(s) - Double(plot.width), scrollX))
        scrollY = max(0, min(Double(contentH(s)) - Double(plot.height), scrollY))
    }

    // MARK: moves

    /// One turn of the wheel at `point` (view coordinates, pixels).
    public mutating func apply(_ input: ArrangementScroll, at point: CGPoint, in s: ArrangementSpace) {
        ensure(in: s)
        let k = s.options.scale
        func notches(_ delta: Double) -> Double { input.precise ? delta / Self.trackpadNotch : delta }
        func move(_ delta: Double, _ notch: Double) -> Double { input.precise ? delta * k : delta * notch * k }
        let single = input.dy != 0 ? input.dy : input.dx
        if input.command {
            zoom(factor: pow(Self.zoomPerNotch, notches(single)), atX: point.x, in: s)
        } else if input.option {
            resizeLanes(by: Int((notches(single) * Self.notchLane * k).rounded()), atY: point.y, in: s)
        } else if input.shift {
            // The time: the wheel's one axis may arrive as either.
            scroll(dx: -move(input.dx != 0 ? input.dx : input.dy, Self.notchTime), dy: 0, in: s)
        } else {
            scroll(dx: -move(input.dx, Self.notchTime), dy: -move(input.dy, Self.notchTracks), in: s)
        }
    }

    /// The time zooms around `x`: the beat under it stays under it. `factor` above 1 zooms in;
    /// the whole song across is as far out as it goes.
    public mutating func zoom(factor: Double, atX x: CGFloat, in s: ArrangementSpace) {
        ensure(in: s)
        guard factor > 0, pxPerBeat > 0 else { return }
        let plot = s.plot
        let inside = Double(max(plot.minX, min(plot.maxX, x)) - plot.minX)
        let beat = (inside + scrollX) / pxPerBeat
        let fit = fitPx(s)
        let px = max(fit, min(maxPx(s), pxPerBeat * factor))
        fitted = px <= fit
        pxPerBeat = px
        scrollX = beat * px - inside
        clamp(in: s)
    }

    /// Taller or lower tracks; the track under `y` stays under it.
    public mutating func resizeLanes(by delta: Int, atY y: CGFloat, in s: ArrangementSpace) {
        ensure(in: s)
        let o = s.options
        let inside = Double(max(0, y - s.plot.minY))
        let lanes = (inside + scrollY) / Double(laneH + ArrangementRender.gap(laneH: laneH, options: o))
        laneH = max(minLane(s), min(maxLane(s), laneH + delta))
        lanesFitted = false
        scrollY = (lanes * Double(laneH + ArrangementRender.gap(laneH: laneH, options: o))).rounded() - inside
        clamp(in: s)
    }

    /// Moves the view by pixels; the content goes the other way.
    public mutating func scroll(dx: Double, dy: Double, in s: ArrangementSpace) {
        scroll(toX: scrollX + dx, y: scrollY + dy, in: s)
    }

    public mutating func scroll(toX x: Double, y: Double, in s: ArrangementSpace) {
        ensure(in: s)
        scrollX = x
        scrollY = y
        clamp(in: s)
    }
}
