import XCTest
@testable import AliveUI
import AliveCore

@MainActor
final class MissingRootUITests: XCTestCase {
    func testReplacingKeepsThePositionAndDropsTheOldOffSwitch() {
        var s = AppSettings()
        s.roots = ["/a", "/old", "/c"]
        s.disabledRoots = ["/old"]
        let next = CatalogModel.replacing("/old", with: "/new", in: s)
        XCTAssertEqual(next?.roots, ["/a", "/new", "/c"])
        XCTAssertEqual(next?.disabledRoots, [])
        XCTAssertNil(CatalogModel.replacing("/old", with: "/c", in: s), "an existing root would double")
        XCTAssertNil(CatalogModel.replacing("/nope", with: "/new", in: s))
    }

    func testMissingRootWordingInBothLanguages() {
        XCTAssertEqual(CommonStrings.rootMissingLine.en.replacingOccurrences(of: "%@", with: "~/Dropbox/_sounds"),
                       "Folder not found: ~/Dropbox/_sounds")
        XCTAssertEqual(CommonStrings.rootMissingLine.ja.replacingOccurrences(of: "%@", with: "~/Dropbox/_sounds"),
                       "フォルダが見つかりません: ~/Dropbox/_sounds")
        XCTAssertEqual(CommonStrings.chooseAgain.ja, "選び直す…")
        XCTAssertEqual(CommonStrings.removeFromList.ja, "登録から外す")
    }

    func testByteSizesFollowTheGivenLocale() {
        let en = Locale(identifier: "en_US"), ja = Locale(identifier: "ja_JP")
        XCTAssertFalse(SetFormat.size(248, locale: en).contains("バイト"))
        XCTAssertTrue(SetFormat.size(248, locale: ja).contains("バイト"))
        XCTAssertFalse(ExportText.bytes(248, locale: en).contains("バイト"))
        XCTAssertTrue(ExportText.bytes(0, locale: en).hasPrefix("0"))
    }
}
