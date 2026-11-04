// Port of src/Theme.cs (colours, radii, insets, type sizes). Layout numbers are upstream's pixel
// values at 96 dpi scaled to macOS points; the colours are exact.
import SwiftUI

extension Color {
    /// `0xRRGGBB` with optional alpha.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    // MARK: Colours
    static let bg = Color(hex: 0x1B1B1D)
    static let surface = Color(hex: 0x28282A)
    static let surfacePressed = Color(hex: 0x3A3A3E)
    /// Between `surface` and `surfacePressed`: hover on quiet controls.
    static let surfaceHover = Color(hex: 0x323235)
    static let sunken = Color(hex: 0x151519)          // the search field
    static let light = Color(hex: 0xCACACB)           // primary button / selected pill
    static let lightTop = Color(hex: 0xF2F2F4)
    static let lightPressed = Color(hex: 0x9E9EA2)
    static let text = Color(hex: 0xE9E9EB)
    static let textDim = Color(hex: 0x919196)
    static let onLight = Color(hex: 0x1B1B1D)
    static let green = Color(hex: 0x61E170)
    static let red = Color(hex: 0xE16161)
    static let rowHover = Color.white.opacity(0.08)   // 0x14 alpha upstream
    static let hairline = Color(hex: 0x3A3A3D)
    /// Keyboard focus ring.
    static let focus = Color(hex: 0x8CB4FF)
    static let cardHighlight = Color.white.opacity(0.08)  // top-edge light of glass cards
    static let cardBorder = Color.white.opacity(0.04)

    // MARK: Semantic text colours (WCAG AA ≥ 4.5:1, measured against bg/surface/surfaceHover/surfacePressed)
    /// Secondary text on any interactive surface (5.1:1 even on `surfacePressed`). `textDim` is only
    /// safe on `bg`/`surface` at rest — use this one for metadata in rows that hover or press.
    static let secondaryText = Color(hex: 0xAEAEB3)
    /// Error/warning figures and labels (4.8:1 on `surfacePressed`); `red` stays for fills and icons.
    static let errorText = Color(hex: 0xFF8585)
    /// Text inside `TagPill` (6.1:1 on the tag's 10 % white fill over `surface`).
    static let tagText = Color(hex: 0xC4C4C8)
    /// Selected table row fill; text on it must be `text` (secondary colours drop below 4.5:1).
    static let tableSelection = Color(hex: 0x4A4A52)

    // MARK: Sizes (points; every one follows Settings → Interface scale through `s`)
    /// `value` at the current interface scale (75 / 100 / 125 %, upstream Theme.Zoom). Read it while
    /// a view builds its `body` and the view follows a scale change at once; kept in a `static let`
    /// it keeps the value it had at its first use.
    static func s(_ value: CGFloat) -> CGFloat { value * ThemeScale.shared.factor }

    static var pad: CGFloat { s(24) }            // window margin (upstream 30 px)
    static var controlH: CGFloat { s(30) }       // every pill and field in the toolbar (35 px)
    static var iconSize: CGFloat { s(30) }       // a round icon button (35 px)
    static var iconGap: CGFloat { s(8) }         // (10 px)
    static var rowH: CGFloat { s(44) }           // table row pitch (57 px)
    static var rowPillH: CGFloat { s(42) }       // the row highlight itself (55 px)
    static var cellPadX: CGFloat { s(18) }       // (24 px)
    static var panelW: CGFloat { s(300) }        // the detail panel (332 px)
    static var panelPad: CGFloat { s(14) }       // (16 px)
    static var windowR: CGFloat { s(18) }
    static var cardR: CGFloat { s(14) }
    static var thumbR: CGFloat { s(6) }
    /// Gap between a list and its inspector panel (Sets, Plugins, Samples use the same).
    static var panelGap: CGFloat { s(16) }

    // MARK: Fonts (SF Pro is the counterpart of Segoe UI)
    static var fTitle: Font { .system(size: s(13), weight: .semibold) }
    static var fBody: Font { .system(size: s(13)) }
    static var fButton: Font { .system(size: s(13)) }
    static var fLabel: Font { .system(size: s(12)) }
    static var fSmall: Font { .system(size: s(12)) }
    static var fBadge: Font { .system(size: s(11)) }
    static var fMini: Font { .system(size: s(9.5)) }
    static var fHead: Font { .system(size: s(17), weight: .semibold) }
    static var fDialogTitle: Font { .system(size: s(22), weight: .semibold) }
    /// Project tile / card titles.
    static var fCardTitle: Font { .system(size: s(15), weight: .semibold) }
    /// Smallest caption that stays legible at 100 % (heatmap months, slider captions): never below 11 pt.
    static var fCaption: Font { .system(size: s(11)) }

    // MARK: Motion
    static let hoverAnimation = Animation.easeOut(duration: 0.12)
    static let selectAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)
}
