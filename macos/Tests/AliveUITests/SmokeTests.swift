import XCTest
@testable import AliveUI

final class UISmokeTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(AliveApp.self)
    }
}
