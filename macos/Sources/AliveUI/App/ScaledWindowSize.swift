// Mac-only: the sizes a window opens with and can be made smallest at, at the interface scale
// (Settings → Interface scale, 75 / 100 / 125 %) and never beyond the room on the screen. Shared by
// the main window and the Stat window (upstream 9ce4b4b grows both with the scale).
import AppKit
import CoreGraphics

struct ScaledWindowSize: Equatable {
    /// The first size, and the smallest the window can be made, in points.
    let ideal: CGSize
    let minimum: CGSize

    /// Both sizes at `uiScale` percent, never larger than `screen` (the room a window can have).
    /// Without the cap a 125 % minimum is wider than a 1280-pt desktop and cannot be fitted on it.
    static func make(uiScale: Int, ideal: CGSize, minimum: CGSize, screen: CGSize? = nil) -> ScaledWindowSize {
        let k = CGFloat(uiScale > 0 ? uiScale : 100) / 100
        func fit(_ base: CGSize) -> CGSize {
            let scaled = CGSize(width: (base.width * k).rounded(), height: (base.height * k).rounded())
            guard let screen else { return scaled }
            return CGSize(width: min(scaled.width, screen.width), height: min(scaled.height, screen.height))
        }
        return ScaledWindowSize(ideal: fit(ideal), minimum: fit(minimum))
    }

    /// The usable area (menu bar and Dock left out) of the screen a new window opens on.
    static var availableRoom: CGSize? { (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size }
}

/// The main window: 1240 × 780 to start with and 1120 × 600 at the least (the top bar must fit in
/// 1120 pt in Japanese, see ARCHITECTURE).
enum MainWindowSize {
    static let baseIdeal = CGSize(width: 1240, height: 780)
    static let baseMinimum = CGSize(width: 1120, height: 600)

    static func make(uiScale: Int, screen: CGSize? = nil) -> ScaledWindowSize {
        ScaledWindowSize.make(uiScale: uiScale, ideal: baseIdeal, minimum: baseMinimum, screen: screen)
    }

    /// At the scale the interface has now, on this screen.
    static var current: ScaledWindowSize {
        make(uiScale: Int((ThemeScale.shared.factor * 100).rounded()), screen: ScaledWindowSize.availableRoom)
    }
}
