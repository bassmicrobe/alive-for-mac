import XCTest
@testable import AliveUI

final class ExportStringsTests: XCTestCase {
    func testTableIsComplete() {
        assertStringTableIsComplete(ExportStrings.self)
    }
}
