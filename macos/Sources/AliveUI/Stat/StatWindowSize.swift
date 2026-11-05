// Port of the window sizing in nebula/NebulaForm.cs (9ce4b4b): upstream opens Stat at 1360 × 860 and
// lets it grow with the screen's scale, because the text grows and an unscaled window cut the hint
// line under the cloud short. On the Mac the screen scale is the system's business; what grows the
// text is the interface scale (Settings → Interface scale, 75 / 100 / 125 %), so that sets the factor.
import CoreGraphics

enum StatWindowSize {
    static let baseIdeal = CGSize(width: 1320, height: 820)
    static let baseMinimum = CGSize(width: 1040, height: 640)

    /// Both sizes at `uiScale` percent, never larger than the room on the screen.
    static func make(uiScale: Int, screen: CGSize? = nil) -> ScaledWindowSize {
        ScaledWindowSize.make(uiScale: uiScale, ideal: baseIdeal, minimum: baseMinimum, screen: screen)
    }
}
