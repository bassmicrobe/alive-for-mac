import XCTest
@testable import AliveUI

final class LiveVersionTests: XCTestCase {
    func testNumericOrdering() {
        XCTAssertLessThan(LiveVersion("11.3.20"), LiveVersion("12.0"))
        XCTAssertLessThan(LiveVersion("12.0"), LiveVersion("12.0.5"))
        XCTAssertLessThan(LiveVersion("9.7.7"), LiveVersion("12.0"))
    }

    func testReleaseBeatsBetaOfSameNumber() {
        XCTAssertLessThan(LiveVersion("12.0b20"), LiveVersion("12.0"))
        XCTAssertLessThan(LiveVersion("12.0b2"), LiveVersion("12.0b10"))
        XCTAssertLessThan(LiveVersion("11.3.20b1"), LiveVersion("11.3.20"))
    }

    func testBetaOfNewerNumberBeatsOlderRelease() {
        XCTAssertLessThan(LiveVersion("11.3.20"), LiveVersion("12.0b1"))
    }

    func testEqualVersions() {
        XCTAssertEqual(LiveVersion("12.0"), LiveVersion("12.0"))
    }
}
