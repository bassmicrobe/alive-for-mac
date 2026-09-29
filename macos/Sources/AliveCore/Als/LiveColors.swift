// Port of src/LiveColors.cs (System.Drawing.Color replaced by a plain RGB struct)
import Foundation

public struct RGBColor: Equatable, Hashable, Sendable {
    public let r: UInt8, g: UInt8, b: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }
    public init(hex: Int) {
        self.init(r: UInt8((hex >> 16) & 0xFF), g: UInt8((hex >> 8) & 0xFF), b: UInt8(hex & 0xFF))
    }
    public var hex: Int { Int(r) << 16 | Int(g) << 8 | Int(b) }
}

/// Live's clip and track palette: 70 colours in a 14×5 grid — the one from a track's context
/// menu. A set stores only the colour number (`<Color Value="23"/>`); the values are baked into
/// Live's binary. The layout was checked against `live_to_push2_colors` in Ableton's own
/// Push 2 stylesheet: five rows of 14, the same order of hues in each row; the 14th column is
/// grey.
public enum LiveColors {
    private static let hex: [Int] = [
        // row 1 — pastels
        0xFD95A7, 0xFDA43A, 0xCB9834, 0xF7F384, 0xC0F932, 0x32FD42, 0x39FDAA,
        0x65FEE8, 0x8DC6FD, 0x5682E1, 0x93A9FC, 0xD670E2, 0xE3569F, 0xFFFFFF,
        // row 2 — saturated
        0xFC393D, 0xF46C20, 0x98714E, 0xFEEE4A, 0x8BFD70, 0x44C121, 0x1EBEAF,
        0x31E9FD, 0x22A5EB, 0x127EBE, 0x8870E1, 0xB579C4, 0xFD42D2, 0xD0D0D0,
        // row 3 — light muted
        0xE0685D, 0xFDA378, 0xD2AC75, 0xEDFEB2, 0xD2E39C, 0xBACF79, 0x9CC38F,
        0xD5FDE2, 0xCEF1F8, 0xB9C2E2, 0xCDBCE3, 0xAE9AE3, 0xE5DCE1, 0xA9A9A9,
        // row 4 — earthy
        0xC5928C, 0xB68259, 0x98836B, 0xBFB96E, 0xA6BC25, 0x7EAF52, 0x8AC2BA,
        0x9CB3C3, 0x86A5C1, 0x8494CA, 0xA596B4, 0xBEA0BD, 0xBB7296, 0x7B7B7B,
        // row 5 — dark
        0xAD3436, 0xA75135, 0x714F42, 0xDAC229, 0x85952B, 0x559E38, 0x1B9B8E,
        0x266383, 0x1B3393, 0x3154A0, 0x624EAB, 0xA24EAB, 0xCA326E, 0x3C3C3C,
    ]

    public static let count = 70

    /// Grey for when no colour was written (older sets) or the index is not ours.
    public static let fallback = RGBColor(r: 0x8E, g: 0x8E, b: 0x93)

    public static func get(_ index: Int) -> RGBColor {
        hex.indices.contains(index) ? RGBColor(hex: hex[index]) : fallback
    }
}
