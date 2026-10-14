import XCTest
import AliveCore
@testable import AliveUI

@MainActor
final class UnreadableStatusTests: XCTestCase {
    override func tearDown() {
        Localizer.shared.preference = .system
        super.tearDown()
    }

    func testUnreadableHasItsOwnWordingIconAndHelp() {
        let status = SetStatus(isUnreadable: true)
        Localizer.shared.preference = .en
        XCTAssertEqual(SetStatusFormat.label(.unreadable), "Can't be read")
        XCTAssertTrue(SetStatusFormat.help(status).contains("Can't be read"))
        Localizer.shared.preference = .ja
        XCTAssertEqual(SetStatusFormat.label(.unreadable), "読み込めません")
        XCTAssertFalse(SetStatusFormat.symbol(.unreadable).isEmpty)
        XCTAssertNotEqual(SetStatusFormat.symbol(.unreadable), SetStatusFormat.symbol(.ready))
    }

    func testEveryReadinessHasWordingInBothLanguages() {
        for readiness in Readiness.allCases {
            Localizer.shared.preference = .en
            XCTAssertFalse(SetStatusFormat.label(readiness).isEmpty, "\(readiness) en")
            Localizer.shared.preference = .ja
            XCTAssertFalse(SetStatusFormat.label(readiness).isEmpty, "\(readiness) ja")
        }
    }

    func testStringTablesStayComplete() {
        assertStringTableIsComplete(SetsStrings.self)
    }
}
