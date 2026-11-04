// Port of Theme.Zoom (src/Theme.cs, 1.3.3): the app's own scale on top of the display's.
// Upstream reads it once at startup (GDI fonts are created once); here every Theme size and font is
// computed from it and it is observable, so a view that reads a metric while building `body`
// follows a change of Settings → Interface scale at once. AppKit supplies the display scale.
import AliveCore
import Foundation
import Observation

@Observable
final class ThemeScale {
    static let shared = ThemeScale()

    /// 0.75, 1 or 1.25 (`Settings.uiScale` / 100).
    private(set) var factor: CGFloat = 1

    /// Takes `Settings.uiScale`; a value outside the offered ones counts as 100.
    func apply(percent: Int) {
        let next = AppSettings.uiScales.contains(percent) ? CGFloat(percent) / 100 : 1
        if next != factor { factor = next }
    }
}
