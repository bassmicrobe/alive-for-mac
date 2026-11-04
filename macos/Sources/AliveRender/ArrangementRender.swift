// Port of src/ArrangementRender.cs (GDI+ Graphics replaced by CoreGraphics / CoreText).
import AliveCore
import CoreGraphics
import CoreText
import Foundation

public struct RenderOptions: Equatable, Sendable {
    /// The track name column on the left.
    public var showNames = false
    /// The bar ruler along the top.
    public var showRuler = false
    public var minLane = 2.0
    public var maxLane = 26.0
    /// Pixels per point (upstream `Dpi`): every size below is multiplied by it.
    public var scale = 1.0

    public init(showNames: Bool = false, showRuler: Bool = false,
                minLane: Double = 2.0, maxLane: Double = 26.0, scale: Double = 1.0) {
        self.showNames = showNames; self.showRuler = showRuler
        self.minLane = minLane; self.maxLane = maxLane; self.scale = scale
    }

    /// Thumbnails on tiles and in the Sets inspector: no text, thin lanes.
    public static let thumbnail = RenderOptions(scale: 1.5)
    /// The big preview: ruler, track names, tall lanes. The names belong here at full size and the
    /// clips carry none (upstream a6c8dc1 dropped the clip captions: they were never legible).
    public static func preview(scale: Double, minLane: Double = 2) -> RenderOptions {
        RenderOptions(showNames: true, showRuler: true, minLane: minLane, maxLane: 40, scale: scale)
    }
}

/// Draws the arrangement the way it looks in Live: tracks as rows from top to bottom, time from
/// left to right, a clip as a rectangle in its own colour. A midi clip's body is muted and the
/// notes are drawn over it — otherwise an empty clip is indistinguishable from a dense one in
/// the preview. Pure CoreGraphics: safe to call from any thread.
public enum ArrangementRender {
    /// Large sets have tens of thousands of notes and the eye is satisfied with a portion.
    static let maxNotesDrawn = 60_000
    static let maxLoopRepeats = 512

    /// Geometry decided from the area and the options; exposed so tests can check it.
    struct Layout: Equatable {
        var gap: Int
        var rulerH: Int
        var laneH: Int
        var nameW: Int
        var top: Int
    }

    /// `wantedNameW` (pixels) is the width the longest track name needs; the name column grows to
    /// it (up to two fifths of the picture and 320 pt) instead of clipping names at a fixed 170 pt.
    static func layout(area: CGRect, trackCount n: Int, options o: RenderOptions, wantedNameW: Int = 0) -> Layout {
        let height = Int(area.height), width = Int(area.width)
        let gap = n > 0 && height / n >= 8 ? px(o, 2) : 1
        let rulerH = o.showRuler ? px(o, 24) : 0
        var laneH = (height - rulerH - gap * (n - 1)) / max(1, n)
        if laneH > px(o, o.maxLane) { laneH = px(o, o.maxLane) }
        if laneH < px(o, o.minLane) { laneH = max(1, px(o, o.minLane)) }
        // The name column is only worth having when the rows are tall enough to hold a name.
        let nameW = laneH >= px(o, 9) ? nameWidth(width: width, options: o, wanted: wantedNameW) : 0
        // Few tracks: centre the block rather than pushing it to the top.
        let totalH = n * laneH + gap * (n - 1)
        let top = Int(area.minY) + rulerH + max(0, (height - rulerH - totalH) / 2)
        return Layout(gap: gap, rulerH: rulerH, laneH: laneH, nameW: nameW, top: top)
    }

    /// The width of the name column: 170 pt (a fifth of the picture at most), grown to the longest
    /// name up to two fifths and 320 pt; none on a narrow picture or without `showNames`.
    static func nameWidth(width: Int, options o: RenderOptions, wanted: Int = 0) -> Int {
        guard o.showNames, width > px(o, 420) else { return 0 }
        let base = min(px(o, 170), width / 5)
        return max(base, min(wanted, min(px(o, 320), width * 2 / 5)))
    }

    /// The height at which every track gets `options.minLane` (for the "taller tracks" preview).
    public static func fullHeight(trackCount n: Int, options o: RenderOptions) -> Int {
        let gap = px(o, 2)
        return px(o, o.minLane) * n + gap * max(0, n - 1) + (o.showRuler ? px(o, 24) : 0)
    }

    /// A finished picture with a transparent background. `nil` for a zero size.
    public static func makeImage(_ a: Arrangement, width: Int, height: Int, options: RenderOptions,
                                 fitAllTracks: Bool = false) -> CGImage? {
        guard width > 0, height > 0,
              let g = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // y down, like GDI: the port keeps upstream's arithmetic.
        g.translateBy(x: 0, y: CGFloat(height))
        g.scaleBy(x: 1, y: -1)
        // Keep logical lane/gap geometry intact and scale the finished drawing uniformly.
        // Quick Look has a fixed bitmap budget, but must still include the final track.
        var drawingScale = options.scale > 0 && options.scale < 1 ? options.scale : 1
        var logicalOptions = options
        if drawingScale < 1 { logicalOptions.scale = 1 }
        if fitAllTracks {
            let fullHeight = Self.fullHeight(trackCount: a.tracks.count, options: logicalOptions)
            if fullHeight > 0 { drawingScale = min(drawingScale, Double(height) / Double(fullHeight)) }
        }
        g.scaleBy(x: drawingScale, y: drawingScale)
        draw(g, area: CGRect(x: 0, y: 0, width: Double(width) / drawingScale,
                             height: Double(height) / drawingScale),
             arrangement: a, options: logicalOptions)
        return g.makeImage()
    }

    /// The whole arrangement fitted into `area`: the thumbnails on Home, the picture in the panel
    /// and the Quick Look page.
    static func draw(_ g: CGContext, area: CGRect, arrangement a: Arrangement, options o: RenderOptions) {
        let n = a.tracks.count
        guard n > 0 else { return }
        let lay = layout(area: area, trackCount: n, options: o,
                         wantedNameW: o.showNames ? nameColumnWidth(a.tracks, o) : 0)
        let totalH = n * lay.laneH + lay.gap * (n - 1)
        let plot = CGRect(x: area.minX + CGFloat(lay.nameW), y: CGFloat(lay.top),
                          width: max(1, area.width - CGFloat(lay.nameW)), height: CGFloat(max(1, totalH)))
        let pxPerBeat = Double(plot.width) / max(a.end, 4)

        g.setShouldAntialias(false)
        paintBody(g, plot: plot, a, o, pxPerBeat: pxPerBeat, laneH: lay.laneH, gap: lay.gap, x0: plot.minX, y0: Int(plot.minY))
        paintText(g, area: area, plot: plot, nameW: lay.nameW, rulerH: lay.rulerH, a, o,
                  pxPerBeat: pxPerBeat, laneH: lay.laneH, gap: lay.gap, x0: plot.minX, y0: Int(plot.minY))
    }

    // MARK: scrolled view

    /// The clips, their notes and the grid at the scale and scroll of `view` (see
    /// `ArrangementViewport`): what the full-screen preview shows. A block of tracks lower than
    /// the area is centred, as the fitted picture centres it. The names and the bar numbers are
    /// `drawViewText`, apart so the view can keep this layer as a picture and lay the text
    /// straight onto the screen.
    public static func drawView(_ g: CGContext, area: CGRect, arrangement a: Arrangement, options o: RenderOptions,
                                view: ArrangementViewport, wantedNameW: Int = 0) {
        guard !a.tracks.isEmpty else { return }
        let plot = plot(area: area, options: o, wantedNameW: wantedNameW)
        g.setShouldAntialias(false)
        paintBody(g, plot: plot, a, o, pxPerBeat: view.pxPerBeat, laneH: view.laneH, gap: gap(laneH: view.laneH, options: o),
                  x0: plot.minX - CGFloat(view.scrollX), y0: viewTop(plot: plot, trackCount: a.tracks.count, options: o, view: view))
    }

    public static func drawViewText(_ g: CGContext, area: CGRect, arrangement a: Arrangement, options o: RenderOptions,
                                    view: ArrangementViewport, wantedNameW: Int = 0) {
        guard !a.tracks.isEmpty else { return }
        let plot = plot(area: area, options: o, wantedNameW: wantedNameW)
        paintText(g, area: area, plot: plot, nameW: Int(plot.minX - area.minX), rulerH: rulerHeight(o), a, o,
                  pxPerBeat: view.pxPerBeat, laneH: view.laneH, gap: gap(laneH: view.laneH, options: o),
                  x0: plot.minX - CGFloat(view.scrollX), y0: viewTop(plot: plot, trackCount: a.tracks.count, options: o, view: view))
    }

    /// The body layer as a finished picture of `size` pixels (transparent background).
    public static func makeViewImage(_ a: Arrangement, size: CGSize, options o: RenderOptions,
                                     view: ArrangementViewport, wantedNameW: Int = 0) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0,
              let g = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        g.translateBy(x: 0, y: CGFloat(height))
        g.scaleBy(x: 1, y: -1)
        drawView(g, area: CGRect(x: 0, y: 0, width: width, height: height), arrangement: a, options: o,
                 view: view, wantedNameW: wantedNameW)
        return g.makeImage()
    }

    /// Where the tracks go in the scrolled view: the area less the name column and the ruler.
    public static func plot(area: CGRect, options o: RenderOptions, wantedNameW: Int = 0) -> CGRect {
        let nameW = nameWidth(width: Int(area.width), options: o, wanted: wantedNameW), rulerH = rulerHeight(o)
        return CGRect(x: area.minX + CGFloat(nameW), y: area.minY + CGFloat(rulerH),
                      width: max(1, area.width - CGFloat(nameW)), height: max(1, area.height - CGFloat(rulerH)))
    }

    /// A digit needs 19 px of height at upstream's size; the ruler keeps that and some air.
    public static func rulerHeight(_ o: RenderOptions) -> Int { o.showRuler ? px(o, 24) : 0 }

    public static func gap(laneH: Int, options o: RenderOptions) -> Int { laneH >= 8 ? px(o, 2) : 1 }

    public static func lanesHeight(trackCount: Int, laneH: Int, options o: RenderOptions) -> Int {
        trackCount * laneH + gap(laneH: laneH, options: o) * max(0, trackCount - 1)
    }

    /// A track is never lower than its name: a line of text and a little air. Lower than that the
    /// names ran into each other, so many tracks scroll instead of squeezing.
    public static func minViewLane(_ o: RenderOptions) -> Int {
        Int(ChartText.lineHeight(size: 11 * o.scale).rounded(.up)) + px(o, 6)
    }

    /// Where the first track's top falls in the view.
    static func viewTop(plot: CGRect, trackCount: Int, options o: RenderOptions, view: ArrangementViewport) -> Int {
        let totalH = lanesHeight(trackCount: trackCount, laneH: view.laneH, options: o)
        return CGFloat(totalH) < plot.height ? Int(plot.minY) + (Int(plot.height) - totalH) / 2
                                             : Int(plot.minY) - Int(view.scrollY.rounded())
    }

    // MARK: painting

    /// The clips, their notes and the grid, whatever the layout: `x0` is where beat 0 falls and
    /// `y0` the first track's top. Nothing leaves `plot` — with the view scrolled, a clip does not
    /// run under the names.
    private static func paintBody(_ g: CGContext, plot: CGRect, _ a: Arrangement, _ o: RenderOptions,
                                  pxPerBeat: Double, laneH: Int, gap: Int, x0: CGFloat, y0: Int) {
        let n = a.tracks.count
        let step = laneH + gap
        let first = min(n, max(0, (Int(plot.minY) - y0) / max(1, step)))
        let blockTop = max(plot.minY, CGFloat(y0))
        let blockBottom = min(plot.maxY, CGFloat(y0 + n * laneH + gap * (n - 1)))

        g.saveGState()
        g.clip(to: plot)
        grid(g, plot: plot, o, end: max(a.end, 4), pxPerBeat: pxPerBeat, bar: barLength(a), x0: x0, top: blockTop, bottom: blockBottom)

        var notesDrawn = 0
        for i in first..<n {
            let t = a.tracks[i]
            let y = CGFloat(y0 + i * step)
            if y > plot.maxY { break }
            // A group has no clips of its own: a strip in its colour keeps the structure visible.
            if t.isGroup && t.clips.isEmpty {
                if t.color >= 0 {
                    g.setFillColor(cg(LiveColors.get(t.color), alpha: 0x66))
                    g.fill(CGRect(x: plot.minX, y: y + CGFloat(laneH / 2),
                                  width: CGFloat(max(2, px(o, 3))), height: CGFloat(max(1, laneH / 6 + 1))))
                }
                continue
            }
            for c in t.clips {
                let cx0 = x0 + CGFloat(c.start * pxPerBeat), cx1 = x0 + CGFloat(c.end * pxPerBeat)
                if cx1 < plot.minX || cx0 > plot.maxX { continue }
                let rect = CGRect(x: cx0, y: y, width: max(1, cx1 - cx0), height: CGFloat(laneH))
                var col = LiveColors.get(c.color >= 0 ? c.color : t.color)
                if c.disabled { col = desaturate(col) }
                let hasNotes = c.isMidi && !(c.notes?.isEmpty ?? true)
                let bodyAlpha = c.disabled ? 0x50 : hasNotes ? 0x59 : 0xEE
                g.setFillColor(cg(col, alpha: bodyAlpha))
                g.fill(rect)
                if hasNotes, notesDrawn < maxNotesDrawn {
                    notesDrawn += drawNotes(g, rect: rect, origin: x0, plot: plot, clip: c, color: col,
                                            pxPerBeat: pxPerBeat, alpha: c.disabled ? 0x90 : 0xFF)
                }
            }
        }
        g.restoreGState()
    }

    /// The names in their column beside `plot` and the bar numbers on the ruler above it. Each is
    /// clipped to its own strip, so a half-scrolled name stays out of the ruler and a number out
    /// of the names.
    private static func paintText(_ g: CGContext, area: CGRect, plot: CGRect, nameW: Int, rulerH: Int,
                                  _ a: Arrangement, _ o: RenderOptions, pxPerBeat: Double, laneH: Int, gap: Int,
                                  x0: CGFloat, y0: Int) {
        let n = a.tracks.count
        let step = laneH + gap
        let first = min(n, max(0, (Int(plot.minY) - y0) / max(1, step)))
        g.saveGState()
        if nameW > 0 {
            g.saveGState()
            g.clip(to: CGRect(x: area.minX, y: plot.minY, width: CGFloat(nameW), height: plot.height))
            for i in first..<n {
                let y = CGFloat(y0 + i * step)
                if y > plot.maxY { break }
                drawName(g, CGRect(x: area.minX, y: y, width: CGFloat(nameW - px(o, 8)), height: CGFloat(laneH)),
                         track: a.tracks[i], laneH: laneH, o: o)
            }
            g.restoreGState()
        }
        if rulerH > 0 {
            g.clip(to: CGRect(x: plot.minX, y: area.minY, width: max(0, area.maxX - plot.minX), height: CGFloat(rulerH)))
            g.setShouldAntialias(true)
            let rTop = area.minY + CGFloat(px(o, 2))
            let rHeight = CGFloat(max(1, rulerH - px(o, 2)))
            for mark in rulerMarks(area: area, plot: plot, o, end: max(a.end, 4), pxPerBeat: pxPerBeat, bar: barLength(a), x0: x0) {
                ChartText.draw(g, mark.label, in: CGRect(x: mark.x + 2, y: rTop, width: CGFloat(px(o, 44)), height: rHeight),
                               size: 11 * o.scale, color: rulerInk, clip: false)
            }
        }
        g.restoreGState()
        g.setShouldAntialias(false)
    }

    // MARK: notes

    /// A midi clip's notes over its body; `origin` is where beat 0 falls, and what lies outside
    /// `plot` is not drawn. Returns how many note boxes were drawn.
    private static func drawNotes(_ g: CGContext, rect: CGRect, origin: CGFloat, plot: CGRect, clip c: ClipBlock,
                                  color: RGBColor, pxPerBeat: Double, alpha: Int) -> Int {
        guard let notes = c.notes else { return 0 }
        let lo = c.minPitch, hi = c.maxPitch
        let span = max(hi - lo + 1, 6)
        let inner = max(2, rect.height - 1)
        let noteH = max(1, inner / CGFloat(span))

        let loopLen = c.loopLength
        let loop = c.loopOn && loopLen > 0.0001
        let contentAtStart = c.loopStart + c.startRelative
        var repeats = 1
        if loop {
            repeats = Int(((c.length + (contentAtStart - c.loopStart)) / loopLen).rounded(.up)) + 1
            repeats = min(max(repeats, 1), maxLoopRepeats)
        }

        var boxes: [CGRect] = []
        outer: for k in 0..<repeats {
            let shift = c.start - contentAtStart + Double(k) * (loop ? loopLen : 0)
            for nt in notes {
                var s = Double(nt.time) + shift
                var e = s + Double(max(nt.duration, 0.05))
                if e <= c.start || s >= c.end { continue }
                s = max(s, c.start)
                e = min(e, c.end)
                let x0 = origin + CGFloat(s * pxPerBeat), x1 = origin + CGFloat(e * pxPerBeat)
                if x1 < plot.minX || x0 > plot.maxX { continue }          // scrolled out of the view
                var y = rect.maxY - CGFloat(Int(nt.pitch) - lo + 1) * noteH - 0.5
                if y < rect.minY { y = rect.minY }
                boxes.append(CGRect(x: x0, y: y, width: max(1, x1 - x0), height: noteH))
                if boxes.count >= maxNotesDrawn { break outer }
            }
        }
        guard !boxes.isEmpty else { return 0 }
        g.setFillColor(cg(color, alpha: alpha))
        g.fill(boxes)
        return boxes.count
    }

    // MARK: grid, ruler, names

    /// The bar's length in beats, in the set's time signature (4 until the parser knows better).
    private static func barLength(_ a: Arrangement) -> Double { a.barBeats > 0 ? a.barBeats : 4 }

    /// How far apart the bar lines stand: whole bars, doubled until they are at least 56 points
    /// apart — a bar each zoomed in, every eighth on a whole song.
    static func gridStep(_ o: RenderOptions, pxPerBeat: Double, bar: Double) -> Double {
        let minStep = Double(px(o, 56)) / max(0.0001, pxPerBeat)
        var step = bar
        while step < minStep { step *= 2 }
        return step
    }

    /// The first line's number at or left of the plot's edge: a scrolled view starts there rather
    /// than at the song's start.
    private static func firstStep(plot: CGRect, x0: CGFloat, step: Double, pxPerBeat: Double) -> Int {
        max(0, Int((Double(plot.minX - x0) / (step * pxPerBeat)).rounded(.down)))
    }

    private static func grid(_ g: CGContext, plot: CGRect, _ o: RenderOptions, end: Double, pxPerBeat: Double,
                             bar: Double, x0: CGFloat, top: CGFloat, bottom: CGFloat) {
        guard bottom > top else { return }
        // The beats are counted from the line's number rather than added up: a 7/8 bar is 3.5
        // beats, and a sum drifts.
        let step = gridStep(o, pxPerBeat: pxPerBeat, bar: bar)
        g.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: Double(0x12) / 255))
        var k = max(1, firstStep(plot: plot, x0: x0, step: step, pxPerBeat: pxPerBeat))
        while Double(k) * step < end {
            let x = x0 + CGFloat(Double(k) * step * pxPerBeat)
            if x > plot.maxX { break }
            g.fill(CGRect(x: x, y: top, width: 1, height: bottom - top))
            k += 1
        }
    }

    /// The bar numbers of the ruler and where they stand: the bar line's number counted in the
    /// set's bars, so a 3/4 or 7/8 set numbers its own bars.
    static func rulerMarks(area: CGRect, plot: CGRect, _ o: RenderOptions, end: Double, pxPerBeat: Double,
                           bar: Double, x0: CGFloat) -> [(x: CGFloat, label: String)] {
        let step = gridStep(o, pxPerBeat: pxPerBeat, bar: bar)
        var marks: [(x: CGFloat, label: String)] = []
        var k = firstStep(plot: plot, x0: x0, step: step, pxPerBeat: pxPerBeat)
        while Double(k) * step < end {
            let beat = Double(k) * step
            let x = x0 + CGFloat(beat * pxPerBeat)
            k += 1
            if x + 2 < plot.minX { continue }              // scrolled in under the names
            if x > area.maxX { break }
            let label = String(Int((beat / bar).rounded()) + 1)
            // A number that does not fit whole is left out: at the right edge "61" came out as "6".
            if x + 2 + CGFloat(ChartText.width(label, size: 11 * o.scale)) > area.maxX { break }
            marks.append((x, label))
        }
        return marks
    }

    /// Pixels the longest of the first tracks' names needs, with its indent and the gap to the plot.
    public static func nameColumnWidth(_ tracks: [TrackLane], _ o: RenderOptions) -> Int {
        var widest = 0.0
        for t in tracks.prefix(400) {
            widest = max(widest, ChartText.width(t.name, size: 11 * o.scale) + Double(t.indent * px(o, 8)))
        }
        return Int(widest.rounded(.up)) + px(o, 12)
    }

    private static func drawName(_ g: CGContext, _ r: CGRect, track t: TrackLane, laneH: Int, o: RenderOptions) {
        guard laneH >= px(o, 9), r.width > 0 else { return }
        // A row can be exactly the font's height: captions get a little more room than the track.
        let indent = CGFloat(t.indent * px(o, 8))
        let box = CGRect(x: r.minX + indent, y: r.minY - CGFloat(px(o, 2)),
                         width: max(0, r.width - indent), height: CGFloat(laneH + px(o, 4)))
        let c = t.color >= 0 ? blend(LiveColors.get(t.color), textRGB, 0.55) : dimRGB
        g.setShouldAntialias(true)
        ChartText.draw(g, t.name, in: box, size: 11 * o.scale, color: cg(c, alpha: 255))
        g.setShouldAntialias(false)
    }

    // MARK: utilities

    private static let rulerInk = CGColor(srgbRed: 0x91 / 255, green: 0x91 / 255, blue: 0x96 / 255, alpha: 1)
    private static let textRGB = RGBColor(hex: 0xE9E9EB)
    private static let dimRGB = RGBColor(hex: 0x919196)

    static func px(_ o: RenderOptions, _ v: Double) -> Int { Int((v * o.scale).rounded()) }

    static func cg(_ c: RGBColor, alpha: Int) -> CGColor {
        CGColor(srgbRed: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255, alpha: Double(alpha) / 255)
    }

    static func desaturate(_ c: RGBColor) -> RGBColor {
        // Split into typed steps: Swift 6.3 (Xcode 26) gives up type-checking the one-line form.
        let red: Double = Double(c.r) * 0.3
        let green: Double = Double(c.g) * 0.59
        let blue: Double = Double(c.b) * 0.11
        let grey: Int = Int(red + green + blue)
        func half(_ channel: UInt8) -> UInt8 { UInt8((Int(channel) + grey) / 2) }
        return RGBColor(r: half(c.r), g: half(c.g), b: half(c.b))
    }

    static func blend(_ a: RGBColor, _ b: RGBColor, _ t: Double) -> RGBColor {
        func mix(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(max(0, min(255, Double(x) + (Double(y) - Double(x)) * t))) }
        return RGBColor(r: mix(a.r, b.r), g: mix(a.g, b.g), b: mix(a.b, b.b))
    }
}

/// One line of text vertically centred in a rectangle of a y-down CoreGraphics context.
enum ChartText {
    /// The advance width of `text` in the system font at `size`.
    static func width(_ text: String, size: Double) -> Double {
        guard !text.isEmpty else { return 0 }
        let font = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    /// The height of one line in the system font at `size`.
    static func lineHeight(size: Double) -> Double {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    /// `text` if it fits in `maxWidth`, else its longest prefix that fits with a trailing "…"; `nil`
    /// when not even two letters and the ellipsis fit.
    static func fitted(_ text: String, size: Double, maxWidth: Double) -> String? {
        if width(text, size: size) <= maxWidth { return text }
        let chars = Array(text)
        var lo = 0, hi = chars.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if width(String(chars[0..<mid]) + "…", size: size) <= maxWidth { lo = mid } else { hi = mid - 1 }
        }
        return lo >= 2 ? String(chars[0..<lo]) + "…" : nil
    }

    static func draw(_ g: CGContext, _ text: String, in rect: CGRect, size: Double, color: CGColor, clip: Bool = true) {
        guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let font = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        g.saveGState()
        if clip { g.clip(to: rect) }
        g.textMatrix = CGAffineTransform(scaleX: 1, y: -1)      // the context is y-down
        g.textPosition = CGPoint(x: rect.minX, y: rect.midY + (ascent - descent) / 2)
        CTLineDraw(line, g)
        g.restoreGState()
    }
}
