import XCTest
@testable import AliveUI

/// The 2026-11-04 screen check: counts name their unit and agree with their number (Home, Sets, Plugins,
/// Stat), and the Home tab follows the interface scale.
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

    /// Home counts projects, Sets counts sets; the noun agrees with the number (every surface picks the
    /// singular text for 1), and Japanese has no plural.
    func testCountsNameTheirUnitAndAgreeWithTheirNumber() {
        Localizer.shared.preference = .en
        XCTAssertEqual(HomeStrings.readyProjects(ready: 24, total: 24), "24 / 24 projects")
        XCTAssertEqual(HomeStrings.readyProjects(ready: 0, total: 1), "0 / 1 project")
        XCTAssertEqual(HomeStrings.projectsShown(12), "12 projects shown")
        XCTAssertEqual(HomeStrings.projectsShown(1), "1 project shown")
        XCTAssertEqual(SetFormat.readyCount(24), "24 sets")
        XCTAssertEqual(SetFormat.readyCount(1), "1 set")
        XCTAssertEqual(SetFormat.shownSummary(projects: 1, sets: 3), "1 project · 3 sets")
        XCTAssertEqual(SetFormat.shownSummary(projects: 1, sets: 1), "1 project · 1 set")
        XCTAssertEqual(SetFormat.matches(1, perProject: false), "1 set matches")
        XCTAssertEqual(PluginsFormat.matches(12), "12 plugins match")
        XCTAssertEqual(PluginsFormat.matches(1), "1 plugin matches")
        XCTAssertEqual(StatStrings.projects(12), "12 projects")
        XCTAssertEqual(StatStrings.projects(1), "1 project")

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
