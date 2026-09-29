import XCTest
@testable import AliveCore
@testable import AliveUI

@MainActor
final class PluginsFormatTests: XCTestCase {
    private func row(name: String = "P", category: String = "", sets: Int = 0, match: MatchKind = .exact, last: Date? = nil) -> PluginRow {
        var st = PluginStat()
        st.name = name; st.sets = sets; st.match = match
        var p = InstalledPlugin(); p.category = category
        st.installed = p
        return PluginRow(stat: st, lastUsed: last)
    }

    override func setUp() async throws {
        Localizer.shared.preference = .en
    }

    func testSetsCellShowsADashForUnused() {
        XCTAssertEqual(PluginsFormat.sets(0), "—")
        XCTAssertEqual(PluginsFormat.sets(103), "103")
        XCTAssertEqual(PluginsFormat.setsPhrase(1), "1 set")
        XCTAssertEqual(PluginsFormat.setsPhrase(5), "5 sets")
    }

    func testLastUsedIsALocalizedDateOrADash() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)          // 2023-11-14
        XCTAssertEqual(PluginsFormat.lastUsed(nil), "—")
        XCTAssertEqual(PluginsFormat.lastUsed(.distantPast), "—")
        XCTAssertTrue(PluginsFormat.lastUsed(date, locale: Locale(identifier: "en_US")).contains("2023"))
        XCTAssertTrue(PluginsFormat.lastUsed(date, locale: Locale(identifier: "ja_JP")).contains("2023"))
        XCTAssertNotEqual(PluginsFormat.lastUsed(date, locale: Locale(identifier: "en_US")),
                          PluginsFormat.lastUsed(date, locale: Locale(identifier: "ja_JP")))
    }

    func testTypeColumnPrefersTheCategoryThenTheRole() {
        XCTAssertEqual(PluginsFormat.type(row(category: "Fx|EQ")), "EQ")
        XCTAssertEqual(PluginsFormat.type(row(category: "Instrument")), "Instrument")
        XCTAssertEqual(PluginsFormat.type(row(category: "Fx")), "Effect")
        XCTAssertEqual(PluginsFormat.type(row(category: "")), "")
    }

    func testStatusRoleAndColumnLabelsFollowTheLanguage() {
        XCTAssertEqual(PluginsFormat.status(.missing), "Not installed")
        XCTAssertEqual(PluginsFormat.role(.instrument), "Instrument")
        XCTAssertEqual(PluginsFormat.column(.vendor), "Developer")
        XCTAssertEqual(PluginsFormat.card(.unused), "Never used")
        Localizer.shared.preference = .ja
        XCTAssertEqual(PluginsFormat.status(.missing), "未インストール")
        XCTAssertEqual(PluginsFormat.column(.vendor), "メーカー")
        XCTAssertEqual(PluginsFormat.setsPhrase(3), "3 セット")
        XCTAssertEqual(PluginsFormat.vendorLabel(PluginFilter.unknownVendor), "不明")
        Localizer.shared.preference = .en
    }

    func testStandInsAreLocalizedButRealNamesAreNot() {
        XCTAssertEqual(PluginsFormat.vendorLabel(PluginFilter.unknownVendor), "Unknown")
        XCTAssertEqual(PluginsFormat.vendorLabel("Xfer"), "Xfer")
        XCTAssertEqual(PluginsFormat.categoryLabel(PluginFilter.otherCategory), "Other")
        XCTAssertEqual(PluginsFormat.categoryLabel("EQ"), "EQ")
        XCTAssertEqual(PluginsFormat.formatLabel("Other"), "Other")
        XCTAssertEqual(PluginsFormat.formatLabel("VST3"), "VST3")
    }

    func testMissingSummaryIsOneSentenceWithTheCount() {
        XCTAssertEqual(PluginsFormat.missingSummary(1), "1 plugin used in your sets isn't installed")
        XCTAssertEqual(PluginsFormat.missingSummary(12), "12 plugins used in your sets aren't installed")
    }

    func testCategoryIsMadeReadable() {
        XCTAssertEqual(PluginsFormat.category("Fx|EQ"), "Fx · EQ")
        XCTAssertEqual(PluginsFormat.category("Instrument"), "Instrument")
        XCTAssertEqual(PluginsFormat.category(""), "")
    }
}
