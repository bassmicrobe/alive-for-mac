import XCTest
@testable import AliveUI

final class LocalizerTests: XCTestCase {
    private var saved: LanguagePreference = .system

    override func setUp() {
        super.setUp()
        saved = Localizer.shared.preference
    }

    override func tearDown() {
        Localizer.shared.preference = saved
        super.tearDown()
    }

    func testSwitchingPreferenceChangesStrings() {
        Localizer.shared.preference = .en
        XCTAssertEqual(CommonStrings.tabHome.s, "Home")
        Localizer.shared.preference = .ja
        XCTAssertEqual(CommonStrings.tabHome.s, "ホーム")
        XCTAssertEqual(Localizer.shared.lang, .ja)
    }

    func testFormatUsesCurrentLanguage() {
        Localizer.shared.preference = .en
        XCTAssertEqual(CommonStrings.shownCount.f(107), "107 shown")
        Localizer.shared.preference = .ja
        XCTAssertEqual(CommonStrings.shownCount.f(107), "107 件を表示")
    }

    func testConfigValueRoundTrip() {
        for option in LanguagePreference.allCases {
            XCTAssertEqual(LanguagePreference(configValue: option.configValue), option)
        }
        XCTAssertEqual(LanguagePreference(configValue: "bogus"), .system)
        XCTAssertEqual(LanguagePreference(configValue: nil), .system)
    }
}
