import XCTest
@testable import AliveUI

final class HelpStringsTests: XCTestCase {
    func testTableIsComplete() {
        assertStringTableIsComplete(HelpStrings.self)
    }
}
