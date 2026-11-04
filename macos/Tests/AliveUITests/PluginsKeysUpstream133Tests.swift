import XCTest
@testable import AliveUI

/// The Plugins tab after upstream 1.3.1-1.3.3 (9ce4b4b, a6c8dc1, 0bb4915).
@MainActor
final class PluginsKeysUpstream133Tests: XCTestCase {
    func testSpaceLeavesTheKeyAloneWhileThePlayerHasNothingLoaded() throws {
        let app = try makeModel()
        XCTAssertFalse(app.plugins.togglePlayerIfLoaded())
    }
}
