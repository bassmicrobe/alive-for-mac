import XCTest
@testable import AliveUI

/// The Plugins tab after upstream 1.3.1-1.3.3 (9ce4b4b, a6c8dc1, 0bb4915).
@MainActor
final class PluginsKeysUpstream133Tests: XCTestCase {
    override func setUp() async throws {
        Localizer.shared.preference = .en
    }

    func testFilterCounterSaysOnePluginMatchesInTheSingular() {
        XCTAssertEqual(PluginsFormat.matches(1), "1 plugin matches")
        XCTAssertEqual(PluginsFormat.matches(12), "12 plugins match")
    }

    func testSpaceLeavesTheKeyAloneWhileThePlayerHasNothingLoaded() throws {
        let app = try makeModel()
        XCTAssertFalse(app.plugins.togglePlayerIfLoaded())
    }
}
