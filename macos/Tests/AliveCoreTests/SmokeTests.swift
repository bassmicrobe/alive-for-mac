import XCTest
@testable import AliveCore

final class SmokeTests: XCTestCase {
    func testZlibIsLinked() {
        XCTAssertFalse(AliveCore.zlibVersion.isEmpty)
    }
}
