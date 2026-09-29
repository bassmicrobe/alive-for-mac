import XCTest
import AliveCore
@testable import AliveUI

private struct Stub: UpdateFetching {
    let status: Int
    var body = Data()
    var error: Error?
    let counter: Counter

    final class Counter: @unchecked Sendable { var calls = 0 }

    func get(_ request: URLRequest) async throws -> (Data, Int) {
        counter.calls += 1
        if let error { throw error }
        return (body, status)
    }
}

private func releaseJSON(_ tag: String, url: String = "https://github.com/bassmicrobe/alive-for-mac/releases/tag/x") -> Data {
    Data("{\"tag_name\":\"\(tag)\",\"name\":\"Alive \(tag)\",\"html_url\":\"\(url)\"}".utf8)
}

@MainActor
final class UpdateModelTests: XCTestCase {
    private func make(current: String = "0.1.0", status: Int = 200, body: Data = releaseJSON("v0.2.0"), error: Error? = nil,
                      day: String = "2026-03-07") -> (UpdateModel, Stub.Counter) {
        let counter = Stub.Counter()
        let stub = Stub(status: status, body: body, error: error, counter: counter)
        return (UpdateModel(currentVersion: current, fetcher: stub, today: { day }), counter)
    }

    private func app(_ cfg: String = "") throws -> AppModel { try makeModel(files: ["settings.cfg": cfg]) }

    // MARK: manual check

    func testManualCheckFindsANewerRelease() async throws {
        let (model, calls) = make()
        let a = try app()
        await model.checkNow(app: a)
        XCTAssertEqual(calls.calls, 1)
        XCTAssertEqual(model.availableRelease?.version, "0.2.0")
        XCTAssertEqual(model.releaseURL?.host, "github.com")
        XCTAssertEqual(a.settings.seenUpdate, "0.2.0", "asked by hand: the dot has nothing left to say")
        XCTAssertEqual(a.settings.lastUpdateCheck, "2026-03-07")
        XCTAssertFalse(model.hasUnseenUpdate)
    }

    func testManualCheckUpToDate() async throws {
        let (model, _) = make(body: releaseJSON("v0.1.0-mac1"))
        let a = try app()
        await model.checkNow(app: a)
        XCTAssertEqual(model.state, .finished(.upToDate(latest: UpdateCheck.Release(version: "0.1.0-mac1", name: "Alive 0.1.0-mac1",
                                                                                     url: "https://github.com/bassmicrobe/alive-for-mac/releases/tag/x"))))
        XCTAssertNil(model.releaseURL)
        XCTAssertEqual(a.settings.seenUpdate, "")
    }

    func testManualCheckNoReleasesYet() async throws {
        let (model, _) = make(status: 404)
        let a = try app()
        await model.checkNow(app: a)
        XCTAssertEqual(model.state, .finished(.noReleases))
        XCTAssertEqual(a.settings.lastUpdateCheck, "2026-03-07", "a clean 404 still counts as a check")
    }

    func testManualCheckFailureIsReportedAndDoesNotStampTheDay() async throws {
        let (model, _) = make(error: URLError(.timedOut))
        let a = try app()
        await model.checkNow(app: a)
        XCTAssertEqual(model.state, .finished(.failed(.unreachable)))
        XCTAssertEqual(a.settings.lastUpdateCheck, "")
    }

    func testDevelopmentBuildIsNeverBehind() async throws {
        let (model, _) = make(current: "dev", body: releaseJSON("v9.9.9"))
        XCTAssertTrue(model.isDevelopmentBuild)
        await model.checkNow(app: try app())
        XCTAssertNil(model.availableRelease)
        guard case .finished(.upToDate) = model.state else { return XCTFail("\(model.state)") }
    }

    // MARK: daily check

    func testDailyCheckDoesNothingWhenSwitchedOff() async throws {
        let (model, calls) = make()
        let a = try app("checkupdates=0\n")
        await model.runDailyCheck(app: a)
        model.dailyCheckIfDue(app: a)
        XCTAssertEqual(calls.calls, 0)
        XCTAssertEqual(model.state, .idle)
    }

    func testDailyCheckLightsTheDotForABigStep() async throws {
        let (model, calls) = make()
        let a = try app("checkupdates=1\n")
        await model.runDailyCheck(app: a)
        XCTAssertEqual(calls.calls, 1)
        XCTAssertTrue(model.hasUnseenUpdate)
        XCTAssertEqual(model.dotVersion, "0.2.0")
        XCTAssertEqual(a.settings.lastUpdateCheck, "2026-03-07")
        XCTAssertEqual(a.settings.seenUpdate, "", "the dot is not 'seen' until the settings open")

        await model.runDailyCheck(app: a)
        XCTAssertEqual(calls.calls, 1, "once a day")

        model.markSeen(app: a)
        XCTAssertFalse(model.hasUnseenUpdate)
        XCTAssertEqual(a.settings.seenUpdate, "0.2.0")
    }

    func testDailyCheckDoesNotRelightForASeenRelease() async throws {
        let (model, _) = make()
        let a = try app("checkupdates=1\nseenupdate=0.2.0\nlastupdatecheck=2026-03-06\n")
        await model.runDailyCheck(app: a)
        XCTAssertFalse(model.hasUnseenUpdate)
        XCTAssertEqual(a.settings.lastUpdateCheck, "2026-03-07")
    }

    func testDailyCheckIgnoresAFix() async throws {
        let (model, _) = make(body: releaseJSON("v0.1.1"))
        let a = try app("checkupdates=1\n")
        await model.runDailyCheck(app: a)
        XCTAssertFalse(model.hasUnseenUpdate, "a fix waits for somebody to ask")
        XCTAssertEqual(model.availableRelease?.version, "0.1.1", "but the settings can still mention it")
    }

    func testDailyCheckIsSilentAboutFailuresButStampsTheDay() async throws {
        let (model, calls) = make(error: URLError(.notConnectedToInternet))
        let a = try app("checkupdates=1\n")
        await model.runDailyCheck(app: a)
        XCTAssertFalse(model.hasUnseenUpdate)
        XCTAssertEqual(model.state, .idle, "no message from the background")
        XCTAssertEqual(a.settings.lastUpdateCheck, "2026-03-07", "no retry on every scan of an offline machine")
        await model.runDailyCheck(app: a)
        XCTAssertEqual(calls.calls, 1)
    }

    func testWritesSettingsThroughTheSharedCfg() async throws {
        let (model, _) = make()
        let a = try app("checkupdates=1\nroot=/tmp/x\n")
        await model.runDailyCheck(app: a)
        let saved = try String(contentsOfFile: AppSettings.filePath(dir: a.dataDir), encoding: .utf8)
        XCTAssertTrue(saved.contains("lastupdatecheck=2026-03-07"))
        XCTAssertTrue(saved.contains("root=/tmp/x"))
    }

    // MARK: version

    func testBundleVersionComesFromTheInfoPlistAndIsDevWhenUnbundled() throws {
        let root = NSTemporaryDirectory() + "alive-bundle-" + UUID().uuidString
        func bundle(_ name: String, plist: [String: Any]) throws -> Bundle {
            let contents = root + "/" + name + ".bundle/Contents"
            try FileManager.default.createDirectory(atPath: contents, withIntermediateDirectories: true)
            (plist as NSDictionary).write(toFile: contents + "/Info.plist", atomically: true)
            return try XCTUnwrap(Bundle(path: root + "/" + name + ".bundle"))
        }
        let versioned = try bundle("A", plist: ["CFBundleIdentifier": "test.a", "CFBundleShortVersionString": " 0.3.1 "])
        XCTAssertEqual(UpdateModel.bundleVersion(versioned), "0.3.1")
        let bare = try bundle("B", plist: ["CFBundleIdentifier": "test.b"])
        XCTAssertEqual(UpdateModel.bundleVersion(bare), "dev")
        let blank = try bundle("C", plist: ["CFBundleIdentifier": "test.c", "CFBundleShortVersionString": "  "])
        XCTAssertEqual(UpdateModel.bundleVersion(blank), "dev")
    }
}

@MainActor
final class UpdatesSectionTextTests: XCTestCase {
    func testEveryOutcomeHasAText() {
        let r = UpdateCheck.Release(version: "0.2.0", name: "Alive 0.2.0")
        let outcomes: [UpdateCheck.Outcome] = [
            .upToDate(latest: r), .newer(r, step: .big), .newer(UpdateCheck.Release(version: "0.2.0"), step: .patch),
            .noReleases, .failed(.rateLimited), .failed(.unreachable), .failed(.unexpectedAnswer),
        ]
        let texts = outcomes.map { UpdatesSection.describe($0) }
        XCTAssertTrue(texts.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(texts[1].contains("0.2.0"))
        XCTAssertEqual(Set(texts).count, texts.count, "each outcome reads differently")
    }

    func testDayText() {
        XCTAssertEqual(UpdatesSection.dayText("not a date"), "not a date")
        XCTAssertTrue(UpdatesSection.dayText("2026-03-07", locale: Locale(identifier: "en_US")).contains("2026"))
    }
}

final class UpdateStringsTests: XCTestCase {
    func testTableIsComplete() {
        assertStringTableIsComplete(UpdateStrings.self)
    }
}
