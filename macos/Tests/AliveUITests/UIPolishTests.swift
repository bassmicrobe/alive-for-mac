// Small pure pieces added by the UI/UX pass: unit-explicit counts, plain read errors, display-only
// trimming, the name column of the preview and the localized VoiceOver states.
import XCTest
@testable import AliveUI

@MainActor
final class UIPolishTests: XCTestCase {
    override func tearDown() {
        Localizer.shared.preference = .system
        super.tearDown()
    }

    func testCountsNameTheirUnits() {
        Localizer.shared.preference = .en
        XCTAssertEqual(CommonStrings.shownProjects.f(553), "553 projects shown")
        XCTAssertEqual(SetsStrings.shownSummary.f(553, 754), "553 projects · 754 sets")
        Localizer.shared.preference = .ja
        XCTAssertEqual(CommonStrings.shownProjects.f(553), "553 件のプロジェクトを表示")
        XCTAssertEqual(SetsStrings.shownSummary.f(553, 754), "553 プロジェクト・754 セット")
    }

    func testReadErrorShowsThePlainSentenceNotTheRawText() {
        Localizer.shared.preference = .en
        let shown = ReadErrorLog.note("XML parse error at line 3", of: "/p/a.als")
        XCTAssertEqual(shown, "This set could not be read. See alive.log for details.")
        XCTAssertFalse(shown.contains("XML"))
        Localizer.shared.preference = .ja
        XCTAssertEqual(ReadErrorLog.note("XML parse error at line 3", of: "/p/a.als"),
                       "このセットを読み込めませんでした。詳細は alive.log を確認してください。")
    }

    func testDisplayNameDropsOnlyLeadingWhitespace() {
        XCTAssertEqual(SetFormat.displayName("  20250224 Project"), "20250224 Project")
        XCTAssertEqual(SetFormat.displayName("A  B "), "A  B ")
    }

    func testHomeAbbreviationKeepsOtherPaths() {
        let home = NSHomeDirectory()
        XCTAssertEqual(SetFormat.homeAbbreviated(home + "/Music/Live"), "~/Music/Live")
        XCTAssertEqual(SetFormat.homeAbbreviated("/Volumes/Work/Live"), "/Volumes/Work/Live")
    }

    func testStateWordsAreLocalized() {
        Localizer.shared.preference = .ja
        XCTAssertEqual(CommonStrings.stateExpanded.s, "展開済み")
        XCTAssertEqual(CommonStrings.stateOff.s, "オフ")
        Localizer.shared.preference = .en
        XCTAssertEqual(CommonStrings.stateCollapsed.s, "Collapsed")
        XCTAssertEqual(CommonStrings.stateOn.s, "On")
    }

    func testNameColumnGrowsToTheLongestTrackName() {
        let short = ArrangementRender.nameColumnWidth([], .preview(scale: 1, minLane: 2))
        XCTAssertLessThan(short, 40)
        var tracks = SyntheticArrangement.make().tracks
        tracks[0].name = "05-01 A very long track name (feat. Somebody Else & Another)"
        let opts = RenderOptions.preview(scale: 1, minLane: 2)
        let wide = ArrangementRender.nameColumnWidth(tracks, opts)
        XCTAssertGreaterThan(wide, 200)
        // The layout follows it (up to two fifths of the picture) instead of clipping at 170.
        let area = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let fixed = ArrangementRender.layout(area: area, trackCount: 3, options: opts)
        let grown = ArrangementRender.layout(area: area, trackCount: 3, options: opts, wantedNameW: wide)
        XCTAssertGreaterThan(grown.nameW, fixed.nameW)
        XCTAssertLessThanOrEqual(grown.nameW, 400)
    }

    func testErrorToastsStayLongerAndCanBeDismissed() async {
        let app = AppModel(dataDir: NSTemporaryDirectory() + "u1-\(UUID().uuidString)")
        app.toast("boom", kind: .error)
        XCTAssertGreaterThan(AppModel.errorToastSeconds, AppModel.infoToastSeconds * 2)
        let id = try? XCTUnwrap(app.toasts.first?.id)
        if let id { app.dismissToast(id) }
        XCTAssertTrue(app.toasts.isEmpty)
    }
}
