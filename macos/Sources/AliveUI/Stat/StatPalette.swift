// Port of nebula/Channels.cs (Gradient, Palette). Foundation only: no SwiftUI here.
import Foundation

/// An sRGB colour with 8-bit channels.
struct RGB8: Equatable {
    var r: Int
    var g: Int
    var b: Int

    init(_ r: Int, _ g: Int, _ b: Int) { self.r = r; self.g = g; self.b = b }

    /// `0xRRGGBB`.
    init(hex: Int) { self.init((hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF) }

    var packed: Int { (r << 16) | (g << 8) | b }
}

/// A named gradient for a continuous value — a set of anchor colours between which
/// `Palette.sample` travels through LAB rather than straight through RGB.
struct StatGradient: Equatable {
    let id: String
    let title: StatStrings
    let stops: [RGB8]
}

enum Palette {
    /// The anchor colours are ordinary sRGB (as they look in any editor), and `sample` mixes
    /// between them through LAB: going straight through RGB between two saturated colours of
    /// differing lightness (say, dark violet and yellow) gives a dirty grey sag in the middle —
    /// the eye sees an accidental blend rather than what was intended. LAB is built so that
    /// lightness changes along a straight line independently of chroma, and the middle stays a
    /// clean colour instead of a grey one.
    static let gradients: [StatGradient] = [
        StatGradient(id: "nebula", title: .gradientNebula, stops: [
            RGB8(0x4C, 0x63, 0xFF), RGB8(0x9B, 0x5C, 0xFF), RGB8(0xEE, 0x5F, 0xC8),
            RGB8(0xFF, 0x77, 0x6B), RGB8(0xFF, 0xC8, 0x4D),
        ]),
        StatGradient(id: "ocean", title: .gradientOcean, stops: [
            RGB8(0x04, 0x12, 0x2B), RGB8(0x0B, 0x3D, 0x5C), RGB8(0x14, 0x7A, 0x96),
            RGB8(0x4F, 0xC6, 0xC0), RGB8(0xEA, 0xFC, 0xF7),
        ]),
    ]

    /// The gradient with this id, or the first for an unknown one.
    static func gradient(id: String) -> StatGradient { gradients.first { $0.id == id } ?? gradients[0] }

    /// "No data": a neutral grey.
    static let noData = RGB8(0x8A, 0x8A, 0x94)
    /// A key or class that is not known.
    static let unknown = RGB8(0x7E, 0x7E, 0x88)

    static func sample(_ grad: StatGradient, _ t: Double) -> RGB8 {
        if t.isNaN { return noData }
        let stops = grad.stops
        let x = min(1, max(0, t)) * Double(stops.count - 1)
        let i = Int(x)
        if i >= stops.count - 1 { return stops[stops.count - 1] }
        return labLerp(stops[i], stops[i + 1], x - Double(i))
    }

    // MARK: LAB
    //
    // sRGB → linear light → XYZ (D65) → CIELAB, and back. The formulas are the textbook ones and
    // are only here so that mixing between two anchor colours takes the shortest road for the eye
    // rather than the shortest road for the numbers R, G and B.

    private static func srgbToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func linearToSrgb(_ c: Double) -> Double {
        let v = min(1, max(0, c))
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    private static let labDelta = 6.0 / 29.0

    private static func labF(_ t: Double) -> Double {
        t > labDelta * labDelta * labDelta ? cbrt(t) : t / (3 * labDelta * labDelta) + 4.0 / 29.0
    }

    private static func labFInv(_ t: Double) -> Double {
        t > labDelta ? t * t * t : 3 * labDelta * labDelta * (t - 4.0 / 29.0)
    }

    static func lab(_ c: RGB8) -> (l: Double, a: Double, b: Double) {
        let r = srgbToLinear(Double(c.r) / 255)
        let g = srgbToLinear(Double(c.g) / 255)
        let b = srgbToLinear(Double(c.b) / 255)
        let x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047
        let y = (r * 0.2126729 + g * 0.7151522 + b * 0.0721750) / 1.0
        let z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883
        let fx = labF(x), fy = labF(y), fz = labF(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    static func rgb(l: Double, a: Double, b: Double) -> RGB8 {
        let fy = (l + 16) / 116
        let fx = fy + a / 500
        let fz = fy - b / 200
        let x = labFInv(fx) * 0.95047
        let y = labFInv(fy) * 1.0
        let z = labFInv(fz) * 1.08883
        let r = x * 3.2404542 + y * -1.5371385 + z * -0.4985314
        let g = x * -0.9692660 + y * 1.8760108 + z * 0.0415560
        let bl = x * 0.0556434 + y * -0.2040259 + z * 1.0572252
        return RGB8(Int((linearToSrgb(r) * 255).rounded()),
                    Int((linearToSrgb(g) * 255).rounded()),
                    Int((linearToSrgb(bl) * 255).rounded()))
    }

    private static func labLerp(_ a: RGB8, _ b: RGB8, _ t: Double) -> RGB8 {
        let p = lab(a), q = lab(b)
        return rgb(l: p.l + (q.l - p.l) * t, a: p.a + (q.a - p.a) * t, b: p.b + (q.b - p.b) * t)
    }

    // MARK: classes

    /// The colour of a key. The hue follows the circle of fifths rather than the chromatic scale:
    /// keys adjacent on the circle are related, and in the cloud they end up adjacent in colour.
    /// Major is lighter and softer, minor is deeper.
    static func key(root: Int, scaleIndex: Int) -> RGB8 {
        guard (0...11).contains(root) else { return unknown }
        let hue = Double((root * 7) % 12) * 30
        let minor = scaleIndex == 1 || scaleIndex == 5 || scaleIndex == 2   // minor / phrygian / dorian
        return fromHSV(h: hue, s: minor ? 0.80 : 0.58, v: minor ? 0.82 : 1.0)
    }

    /// A class colour: hues are laid out by the golden angle so neighbouring numbers do not blend
    /// together.
    static func classColor(_ index: Int) -> RGB8 {
        guard index >= 0 else { return unknown }
        let hue = (Double(index) * 137.508).truncatingRemainder(dividingBy: 360)
        let sat = 0.62 + Double(index % 3) * 0.09
        let val = 1.0 - Double(index % 2) * 0.16
        return fromHSV(h: hue, s: sat, v: val)
    }

    static func fromHSV(h: Double, s: Double, v: Double) -> RGB8 {
        let hh = ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let i = Int(hh / 60) % 6
        let f = hh / 60 - Double(Int(hh / 60))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return RGB8(Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
