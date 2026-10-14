import XCTest
@testable import AliveCore

final class SetStatusTests: XCTestCase {
    func testReadinessPrecedence() {
        XCTAssertEqual(SetStatus().readiness, .ready)
        XCTAssertEqual(SetStatus(offlineFiles: 2, offlineVolumes: ["LaCie"]).readiness, .offline)
        XCTAssertEqual(SetStatus(missingPlugins: nil).readiness, .unknown)
        XCTAssertEqual(SetStatus(offlineFiles: 1, missingPlugins: 3).readiness, .missingPlugins)
        XCTAssertEqual(SetStatus(offlineFiles: 1, missingFiles: 1, missingPlugins: 3).readiness, .missingFiles)
        XCTAssertEqual(SetStatus(offlineFiles: 1, missingPlugins: nil).readiness, .offline)
    }

    func testStaleRenderToleratesASaveRightAfterExport() {
        let render = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(SetStatus.isStale(setModified: render.addingTimeInterval(60), newestRender: render))
        XCTAssertTrue(SetStatus.isStale(setModified: render.addingTimeInterval(3600), newestRender: render))
        XCTAssertFalse(SetStatus.isStale(setModified: render, newestRender: nil))
    }

    func testBasicStatusFollowsInventoryAvailability() {
        var entry = SetEntry()
        entry.path = "/x/a.als"
        entry.missingFiles = 2
        entry.missingPlugins = 1
        XCTAssertEqual(SetStatus.basic(entry, pluginsKnown: true).readiness, .missingFiles)
        entry.missingFiles = 0
        XCTAssertEqual(SetStatus.basic(entry, pluginsKnown: true).readiness, .missingPlugins)
        XCTAssertEqual(SetStatus.basic(entry, pluginsKnown: false).readiness, .unknown)
    }
}
