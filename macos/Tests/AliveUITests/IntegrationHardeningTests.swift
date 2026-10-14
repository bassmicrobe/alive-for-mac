import XCTest
import AliveCore
@testable import AliveUI

final class OpenedURLsTests: XCTestCase {
    func testSchemeURLsNeverBecomeFilePaths() {
        let urls = [URL(string: "alive://open/Users/me/Other/secret.als")!,
                    URL(string: "alive://open?path=/x/y.als")!,
                    URL(fileURLWithPath: "/Users/me/Music/a.als"),
                    URL(fileURLWithPath: "/Users/me/Music/readme.txt")]
        let parts = OpenedURLs.partition(urls)
        XCTAssertEqual(parts.commands.count, 2)
        XCTAssertEqual(parts.alsPaths, ["/Users/me/Music/a.als"])
    }

    func testOtherSchemesEndingInAlsAreIgnored() {
        let parts = OpenedURLs.partition([URL(string: "https://example.com/a.als")!])
        XCTAssertTrue(parts.commands.isEmpty)
        XCTAssertTrue(parts.alsPaths.isEmpty)
    }
}

final class MainWindowRoutingTests: XCTestCase {
    @MainActor func testPresenterDecision() {
        XCTAssertEqual(MainWindowPresenter.decide(hasMainWindow: true, hasOpener: false), .raiseExisting)
        XCTAssertEqual(MainWindowPresenter.decide(hasMainWindow: false, hasOpener: true), .reopen)
        XCTAssertEqual(MainWindowPresenter.decide(hasMainWindow: false, hasOpener: false), .nothing)
    }

    func testNavigationURLsPresentTheMainWindow() {
        XCTAssertTrue(URLAction.showHome.presentsMainWindow)
        XCTAssertTrue(URLAction.showSets(query: "x").presentsMainWindow)
        XCTAssertTrue(URLAction.showSamples(query: "").presentsMainWindow)
        XCTAssertTrue(URLAction.select(path: "/a.als", openInLive: false).presentsMainWindow)
        XCTAssertFalse(URLAction.select(path: "/a.als", openInLive: true).presentsMainWindow)
        XCTAssertFalse(URLAction.rescan.presentsMainWindow)
        XCTAssertFalse(URLAction.showStat.presentsMainWindow)
    }
}

final class FinderTagWorkerTests: XCTestCase {
    private func scratch() throws -> String {
        let dir = NSTemporaryDirectory() + "alive-ui-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func tags(of dir: String) throws -> [String] {
        try URL(fileURLWithPath: dir).resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
    }

    func testGateRefusesWorkWhileDisabledAndSupersedes() {
        let gate = FinderTagGate()
        XCTAssertNil(gate.begin(), "switched off: no ticket")
        gate.enable()
        let first = gate.begin()!
        let second = gate.begin()!
        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.isCurrent(second))
        gate.disable()
        XCTAssertFalse(gate.isCurrent(second))
        XCTAssertNil(gate.begin())
    }

    func testQueuedWorkIsDroppedAfterDisable() async throws {
        let data = try scratch(), project = try scratch()
        let worker = FinderTagWorker(dataDir: data)
        worker.gate.enable()
        let ticket = worker.gate.begin()!
        worker.gate.disable()
        let changed = await worker.run(desired: [project: ["drums"]], ticket: ticket)
        XCTAssertEqual(changed, 0)
        XCTAssertEqual(try tags(of: project), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: data + "/findertags.cfg"))
    }

    func testSupersededRequestDoesNotOverwriteTheNewerOne() async throws {
        let data = try scratch(), project = try scratch()
        let worker = FinderTagWorker(dataDir: data)
        worker.gate.enable()
        let old = worker.gate.begin()!
        let new = worker.gate.begin()!
        // Arrives in the wrong order: the newer wins and the older is dropped.
        await worker.run(desired: [project: ["new"]], ticket: new)
        await worker.run(desired: [project: ["old"]], ticket: old)
        XCTAssertEqual(try tags(of: project), ["new"])
        XCTAssertEqual(FinderTagSync(dataDir: data).loadRecord()[project], ["new"])
    }

    func testSyncStopsBeforeTheNextFolderWhenToldTo() throws {
        let data = try scratch(), a = try scratch(), b = try scratch()
        var allowed = 1
        let changed = FinderTagSync(dataDir: data).sync(desired: [a: ["x"], b: ["x"]]) {
            defer { allowed -= 1 }
            return allowed > 0
        }
        XCTAssertEqual(changed, 1)
        let record = FinderTagSync(dataDir: data).loadRecord()
        XCTAssertEqual(record.count, 1, "only the folder actually written is recorded")
    }
}
