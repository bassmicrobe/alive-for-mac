// Port of the window sizing in nebula/NebulaForm.cs (9ce4b4b): upstream opens Stat at 1360 × 860 and
// lets it grow with the screen's scale, because the text grows and an unscaled window cut the hint
// line under the cloud short. On the Mac the screen scale is the system's business; what grows the
// text is the interface scale (Settings → Interface scale, 75 / 100 / 125 %), so that sets the factor.
import CoreGraphics

struct StatWindowSize: Equatable {
    /// The first size, and the smallest the window can be made, in points.
    let ideal: CGSize
    let minimum: CGSize

    static let baseIdeal = CGSize(width: 1320, height: 820)
    static let baseMinimum = CGSize(width: 1040, height: 640)

    /// Both sizes at `uiScale` percent, never larger than the room on the screen.
    static func make(uiScale: Int, screen: CGSize? = nil) -> StatWindowSize {
        let k = CGFloat(uiScale > 0 ? uiScale : 100) / 100
        func fit(_ base: CGSize) -> CGSize {
            let scaled = CGSize(width: (base.width * k).rounded(), height: (base.height * k).rounded())
            guard let screen else { return scaled }
            return CGSize(width: min(scaled.width, screen.width), height: min(scaled.height, screen.height))
        }
        return StatWindowSize(ideal: fit(baseIdeal), minimum: fit(baseMinimum))
    }
}
