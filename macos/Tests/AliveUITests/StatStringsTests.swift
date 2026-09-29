import XCTest
@testable import AliveUI

final class StatStringsTests: XCTestCase {
    func testTableIsComplete() {
        assertStringTableIsComplete(StatStrings.self)
    }
}
