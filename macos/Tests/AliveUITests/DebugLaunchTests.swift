import XCTest
@testable import AliveUI

@MainActor
final class DebugLaunchTests: XCTestCase {
    func testSheetNamesMapToSheets() {
        XCTAssertEqual(DebugLaunch.sheet(named: "help", selected: nil)?.id, AppSheet.help.id)
        XCTAssertEqual(DebugLaunch.sheet(named: "roots-samples", selected: nil)?.id, AppSheet.roots(.samples).id)
        XCTAssertEqual(DebugLaunch.sheet(named: "preview", selected: "/a.als")?.id, AppSheet.preview(path: "/a.als").id)
    }

    func testSetSheetsNeedASelection() {
        XCTAssertNil(DebugLaunch.sheet(named: "rescue", selected: nil))
        XCTAssertNil(DebugLaunch.sheet(named: "nonsense", selected: "/a.als"))
    }
}
