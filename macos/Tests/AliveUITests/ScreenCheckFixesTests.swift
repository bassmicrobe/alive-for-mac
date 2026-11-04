import XCTest
@testable import AliveUI

/// The 2026-11-04 screen check: counts name their unit, and the Home tab follows the interface scale.
@MainActor
final class ScreenCheckFixesTests: XCTestCase {
    private var saved: LanguagePreference = .system

    override func setUp() {
        super.setUp()
        saved = Localizer.shared.preference
    }

    override func tearDown() {
        Localizer.shared.preference = saved
        ThemeScale.shared.apply(percent: 100)
        super.tearDown()
    }

    /// Home counts projects, Sets counts sets; the noun agrees with the total, and Japanese has no plural.
    func testReadyCountsNameTheirUnit() {
        Localizer.shared.preference = .en
        XCTAssertEqual(HomeStrings.readyProjects(ready: 24, total: 24), "24 / 24 projects")
        XCTAssertEqual(HomeStrings.readyProjects(ready: 0, total: 1), "0 / 1 project")
        XCTAssertEqual(SetFormat.readyCount(24), "24 sets")
        XCTAssertEqual(SetFormat.readyCount(1), "1 set")

        Localizer.shared.preference = .ja
        XCTAssertEqual(HomeStrings.readyProjects(ready: 24, total: 24), "24 / 24 プロジェクト")
        XCTAssertEqual(HomeStrings.readyProjects(ready: 1, total: 1), "1 / 1 プロジェクト")
        XCTAssertEqual(SetFormat.readyCount(24), "24 セット")
        XCTAssertEqual(SetFormat.readyCount(1), "1 セット")
    }

    /// Tiles, the calendar and the overview column were fixed numbers once: at 125 % the window grew
    /// and they did not.
    func testHomeMetricsFollowTheInterfaceScale() {
        ThemeScale.shared.apply(percent: 125)
        XCTAssertEqual(HomeContentColumns.targetTileWidth, 312.5, accuracy: 0.001)
        XCTAssertEqual(HomeContentColumns.gap, 20, accuracy: 0.001)
        XCTAssertEqual(HeatmapMetrics(cols: 53, available: 4000).cell, 17.5, accuracy: 0.001)
        XCTAssertEqual(OverviewPanel.contentWidth(for: 800), 700, accuracy: 0.001)

        ThemeScale.shared.apply(percent: 75)
        XCTAssertEqual(HomeContentColumns.targetTileWidth, 187.5, accuracy: 0.001)
        XCTAssertEqual(HeatmapMetrics(cols: 53, available: 100).cell, 5.25, accuracy: 0.001)
    }
}
