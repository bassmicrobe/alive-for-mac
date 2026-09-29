import XCTest
@testable import AliveUI

final class RescueStringsTests: XCTestCase {
    func testTableIsComplete() {
        assertStringTableIsComplete(RescueStrings.self)
    }
}
