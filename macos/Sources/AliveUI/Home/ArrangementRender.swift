// Port of src/ArrangementRender.cs (GDI+ Graphics replaced by CoreGraphics / CoreText).
import AliveCore
import CoreGraphics
import CoreText
import Foundation

struct RenderOptions: Equatable {
    /// The track name column on the left.
    var showNames = false
    /// The bar ruler along the top.
    var showRuler = false
    /// Clip names inside the blocks.
    var showClipNames = false
    var minLane = 2.0
    var maxLane = 26.0
    /// Pixels per point (upstream `Dpi`): every size below is multiplied by it.
    var scale = 1.0

    /// Thumbnails on tiles and in the Sets inspector: no text, thin lanes.
    static let thumbnail = RenderOptions(scale: 1.5)
    /// The big preview: ruler, names, clip names, tall lanes.
    static func preview(scale: Double, minLane: Double = 2) -> RenderOptions {
        RenderOptions(showNames: true, showRuler: true, showClipNames: true, minLane: minLane, maxLane: 40, scale: scale)
    }
}

/// Draws the arrangement the way it looks in Live: tracks as rows from top to bottom, time from
/// left to right, a clip as a rectangle in its own colour. A midi clip's body is muted and the
/// notes are drawn over it — otherwise an empty clip is indistinguishable from a dense one in
/// the preview. Pure CoreGraphics: safe to call from any thread.
enum ArrangementRender {
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

    static func layout(area: CGRect, trackCount n: Int, options o: RenderOptions) -> Layout {
        let height = Int(area.height), width = Int(area.width)
        let gap = n > 0 && height / n >= 8 ? px(o, 2) : 1
        let rulerH = o.showRuler ? px(o, 24) : 0
        var laneH = (height - rulerH - gap * (n - 1)) / max(1, n)
        if laneH > px(o, o.maxLane) { laneH = px(o, o.maxLane) }
        if laneH < px(o, o.minLane) { laneH = max(1, px(o, o.minLane)) }
        // The name column is only worth having when the rows are tall enough to hold a name.
        var nameW = 0
        if o.showNames, width > px(o, 420), laneH >= px(o, 9) { nameW = min(px(o, 170), width / 5) }
        // Few tracks: centre the block rather than pushing it to the top.
        let totalH = n * laneH + gap * (n - 1)
        let top = Int(area.minY) + rulerH + max(0, (height - rulerH - totalH) / 2)
        return Layout(gap: gap, rulerH: rulerH, laneH: laneH, nameW: nameW, top: top)
    }

    /// The height at which every track gets `options.minLane` (for the "taller tracks" preview).
    static func fullHeight(trackCount n: Int, options o: RenderOptions) -> Int {
        let gap = px(o, 2)
        return px(o, o.minLane) * n + gap * max(0, n - 1) + (o.showRuler ? px(o, 24) : 0)
    }

    /// A finished picture with a transparent background. `nil` for a zero size.
    static func makeImage(_ a: Arrangement, width: Int, height: Int, options: RenderOptions) -> CGImage? {
        guard width > 0, height > 0,
              let g = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // y down, like GDI: the port keeps upstream's arithmetic.
        g.translateBy(x: 0, y: CGFloat(height))
        g.scaleBy(x: 1, y: -1)
        draw(g, area: CGRect(x: 0, y: 0, width: width, height: height), arrangement: a, options: options)
        return g.makeImage()
    }

    static func draw(_ g: CGContext, area: CGRect, arrangement a: Arrangement, options o: RenderOptions) {
        let n = a.tracks.count
        guard n > 0 else { return }
        let lay = layout(area: area, trackCount: n, options: o)
        let totalH = n * lay.laneH + lay.gap * (n - 1)
        let plot = CGRect(x: area.minX + CGFloat(lay.nameW), y: CGFloat(lay.top),
                          width: max(1, area.width - CGFloat(lay.nameW)), height: CGFloat(max(1, totalH)))
        let end = max(a.end, 4)
        let pxPerBeat = Double(plot.width) / end

        g.setShouldAntialias(false)
        gridAndRuler(g, area: area, plot: plot, o: o, end: end, pxPerBeat: pxPerBeat, rulerH: lay.rulerH)

        var notesDrawn = 0
        for (i, t) in a.tracks.enumerated() {
            let y = plot.minY + CGFloat(i * (lay.laneH + lay.gap))
            if y > plot.maxY { break }
            if lay.nameW > 0 {
                drawName(g, CGRect(x: area.minX, y: y, width: CGFloat(lay.nameW - px(o, 8)), height: CGFloat(lay.laneH)),
                         track: t, laneH: lay.laneH, o: o)
            }
            // A group has no clips of its own: a strip in its colour keeps the structure visible.
            if t.isGroup && t.clips.isEmpty {
                if t.color >= 0 {
                    g.setFillColor(cg(LiveColors.get(t.color), alpha: 0x66))
                    g.fill(CGRect(x: plot.minX, y: y + CGFloat(lay.laneH / 2),
                                  width: CGFloat(max(2, px(o, 3))), height: CGFloat(max(1, lay.laneH / 6 + 1))))
                }
                continue
            }
            for c in t.clips {
                let x0 = plot.minX + CGFloat(c.start * pxPerBeat), x1 = plot.minX + CGFloat(c.end * pxPerBeat)
                if x1 < plot.minX || x0 > plot.maxX { continue }
                let w = max(1, x1 - x0)
                let rect = CGRect(x: x0, y: y, width: w, height: CGFloat(lay.laneH))
                var col = LiveColors.get(c.color >= 0 ? c.color : t.color)
                if c.disabled { col = desaturate(col) }
                let hasNotes = c.isMidi && !(c.notes?.isEmpty ?? true)
                let bodyAlpha = c.disabled ? 0x50 : hasNotes ? 0x59 : 0xEE
                g.setFillColor(cg(col, alpha: bodyAlpha))
                g.fill(rect)
                if hasNotes, notesDrawn < maxNotesDrawn {
                    notesDrawn += drawNotes(g, rect: rect, plot: plot, clip: c, color: col,
                                            pxPerBeat: pxPerBeat, alpha: c.disabled ? 0x90 : 0xFF)
                }
                if o.showClipNames, lay.laneH >= px(o, 13), w >= CGFloat(px(o, 44)), !c.name.isEmpty {
                    g.setShouldAntialias(true)
                    ChartText.draw(g, c.name, in: CGRect(x: rect.minX + 3, y: rect.minY, width: rect.width - 5, height: rect.height),
                                   size: 11 * o.scale, color: ink)
                    g.setShouldAntialias(false)
                }
            }
        }
    }

    // MARK: notes

    /// Returns how many note boxes were drawn.
    private static func drawNotes(_ g: CGContext, rect: CGRect, plot: CGRect, clip c: ClipBlock,
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
                let x0 = plot.minX + CGFloat(s * pxPerBeat), x1 = plot.minX + CGFloat(e * pxPerBeat)
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

    private static func gridAndRuler(_ g: CGContext, area: CGRect, plot: CGRect, o: RenderOptions,
                                     end: Double, pxPerBeat: Double, rulerH: Int) {
        // Lines on the bar, but no denser than one per 56 points.
        let minStep = Double(px(o, 56)) / max(0.0001, pxPerBeat)
        var step = 16.0                                     // 4 bars
        while step < minStep { step *= 2 }

        g.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: Double(0x12) / 255))
        var beat = step
        while beat < end {
            g.fill(CGRect(x: plot.minX + CGFloat(beat * pxPerBeat), y: plot.minY, width: 1, height: plot.height))
            beat += step
        }
        guard rulerH > 0 else { return }
        g.setShouldAntialias(true)
        let rTop = area.minY + CGFloat(px(o, 2))
        let rHeight = CGFloat(max(1, rulerH - px(o, 2)))
        beat = 0
        while beat < end {
            let x = plot.minX + CGFloat(beat * pxPerBeat)
            ChartText.draw(g, String(Int(beat / 4) + 1), in: CGRect(x: x + 2, y: rTop, width: CGFloat(px(o, 44)), height: rHeight),
                           size: 11 * o.scale, color: rulerInk, clip: false)
            beat += step
        }
        g.setShouldAntialias(false)
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

    static let ink = CGColor(srgbRed: 0x10 / 255, green: 0x10 / 255, blue: 0x12 / 255, alpha: 0xD0 / 255)
    private static let rulerInk = CGColor(srgbRed: 0x91 / 255, green: 0x91 / 255, blue: 0x96 / 255, alpha: 1)
    private static let textRGB = RGBColor(hex: 0xE9E9EB)
    private static let dimRGB = RGBColor(hex: 0x919196)

    static func px(_ o: RenderOptions, _ v: Double) -> Int { Int((v * o.scale).rounded()) }

    static func cg(_ c: RGBColor, alpha: Int) -> CGColor {
        CGColor(srgbRed: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255, alpha: Double(alpha) / 255)
    }

    static func desaturate(_ c: RGBColor) -> RGBColor {
        let grey = Int(Double(c.r) * 0.3 + Double(c.g) * 0.59 + Double(c.b) * 0.11)
        return RGBColor(r: UInt8((Int(c.r) + grey) / 2), g: UInt8((Int(c.g) + grey) / 2), b: UInt8((Int(c.b) + grey) / 2))
    }

    static func blend(_ a: RGBColor, _ b: RGBColor, _ t: Double) -> RGBColor {
        func mix(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(max(0, min(255, Double(x) + (Double(y) - Double(x)) * t))) }
        return RGBColor(r: mix(a.r, b.r), g: mix(a.g, b.g), b: mix(a.b, b.b))
    }
}

/// One line of text vertically centred in a rectangle of a y-down CoreGraphics context.
enum ChartText {
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
