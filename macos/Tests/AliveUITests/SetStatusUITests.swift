import XCTest
import AliveCore
@testable import AliveUI

@MainActor
final class SetStatusUITests: XCTestCase {
    private var saved: LanguagePreference = .system

    override func setUp() {
        super.setUp()
        saved = Localizer.shared.preference
        Localizer.shared.preference = .en
    }

    override func tearDown() {
        Localizer.shared.preference = saved
        super.tearDown()
    }

    private func entry(_ name: String) -> SetEntry {
        var s = SetEntry()
        s.path = "/lib/\(name)/\(name).als"
        s.name = name
        s.modified = Date(timeIntervalSince1970: 1_000)
        return s
    }

    func testPipelineReadyOnlyUsesTheStatusSource() {
        let sets = [entry("ok"), entry("away")]
        var input = SetsPipeline.Input(sets: sets)
        input.filter.readiness = [.ready]
        input.statusOf = { $0.name == "away" ? SetStatus(offlineFiles: 2, offlineVolumes: ["LaCie"]) : SetStatus() }
        XCTAssertEqual(SetsPipeline.make(input).heads.map(\.name), ["ok"])
    }

    func testOfflineLineNamesTheDriveAndCountsFiles() {
        let status = SetStatus(offlineFiles: 12, offlineVolumes: ["LaCie RAID 8TB"])
        XCTAssertEqual(SetStatusFormat.offlineLine(status), "LaCie RAID 8TB isn't connected (12 files)")
        XCTAssertNil(SetStatusFormat.offlineLine(SetStatus()))
    }

    func testStaleLineCarriesTheRenderDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 12))!
        let stale = SetStatus(newestRender: date, renderIsStale: true)
        XCTAssertEqual(SetStatusFormat.staleLine(stale, calendar: cal), "The render is older than the set (exported 2026-05-01)")
        XCTAssertNil(SetStatusFormat.staleLine(SetStatus(newestRender: date), calendar: cal))
    }

    func testEveryReadinessHasWordingAndSymbol() {
        for r in Readiness.allCases {
            XCTAssertFalse(SetStatusFormat.label(r).isEmpty)
            XCTAssertFalse(SetStatusFormat.symbol(r).isEmpty)
        }
        XCTAssertEqual(SetStatusFormat.label(.unknown), "Plugin status unknown")
    }

    func testJapaneseWording() {
        Localizer.shared.preference = .ja
        XCTAssertEqual(SetStatusFormat.label(.offline), "外付けドライブ未接続")
        XCTAssertEqual(SetsStrings.readyNow.s, "今すぐ開ける")
    }
}
