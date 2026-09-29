import XCTest
@testable import AliveUI

final class SettingsStringsTests: XCTestCase {
    func testTableIsComplete() {
        assertStringTableIsComplete(SettingsStrings.self)
    }
}
