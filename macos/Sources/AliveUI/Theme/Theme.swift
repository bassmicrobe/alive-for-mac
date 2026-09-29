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

    // MARK: Sizes (points)
    static let pad: CGFloat = 24            // window margin (upstream 30 px)
    static let controlH: CGFloat = 30       // every pill and field in the toolbar (35 px)
    static let iconSize: CGFloat = 30       // a round icon button (35 px)
    static let iconGap: CGFloat = 8         // (10 px)
    static let rowH: CGFloat = 44           // table row pitch (57 px)
    static let rowPillH: CGFloat = 42       // the row highlight itself (55 px)
    static let cellPadX: CGFloat = 18       // (24 px)
    static let panelW: CGFloat = 300        // the detail panel (332 px)
    static let panelPad: CGFloat = 14       // (16 px)
    static let windowR: CGFloat = 18
    static let cardR: CGFloat = 14
    static let thumbR: CGFloat = 6
    /// Gap between a list and its inspector panel (Sets, Plugins, Samples use the same).
    static let panelGap: CGFloat = 16

    // MARK: Fonts (SF Pro is the counterpart of Segoe UI)
    static let fTitle = Font.system(size: 13, weight: .semibold)
    static let fBody = Font.system(size: 13)
    static let fButton = Font.system(size: 13)
    static let fLabel = Font.system(size: 12)
    static let fSmall = Font.system(size: 12)
    static let fBadge = Font.system(size: 11)
    static let fMini = Font.system(size: 9.5)
    static let fHead = Font.system(size: 17, weight: .semibold)
    static let fDialogTitle = Font.system(size: 22, weight: .semibold)
    /// Project tile / card titles.
    static let fCardTitle = Font.system(size: 15, weight: .semibold)
    /// Smallest caption that stays legible (heatmap months, slider captions): never below 11 pt.
    static let fCaption = Font.system(size: 11)

    // MARK: Motion
    static let hoverAnimation = Animation.easeOut(duration: 0.12)
    static let selectAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)
}
