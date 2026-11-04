import XCTest
@testable import AliveCore
@testable import AliveUI

/// 233f60a: Settings → Interface scale (75 / 100 / 125 %) multiplies every Theme metric.
@MainActor
final class ThemeScaleUpstream133Tests: XCTestCase {
    func testInterfaceScaleFollowsTheSetting() throws {
        defer { ThemeScale.shared.apply(percent: 100) }
        let app = try makeModel(files: ["settings.cfg": "uiscale=75\n"])
        XCTAssertEqual(Theme.controlH, 22.5, accuracy: 0.001, "the saved scale is applied at launch")

        app.prefs.uiScale = 125
        XCTAssertEqual(Theme.controlH, 37.5, accuracy: 0.001, "changing it applies at once")
        XCTAssertEqual(Theme.s(1120), 1400, accuracy: 0.001)
        XCTAssertEqual(AppSettings.load(dir: app.dataDir).uiScale, 125, "and is saved")

        app.prefs.uiScale = 110
        XCTAssertEqual(app.prefs.uiScale, 125, "only 75, 100 and 125 are offered")
    }
}
