import XCTest
@testable import AliveCore

/// A fetcher that never touches the network: it answers with what the test set up.
struct StubFetcher: UpdateFetching {
    var result: Result<(Data, Int), Error>
    var onRequest: (@Sendable (URLRequest) -> Void)?

    func get(_ request: URLRequest) async throws -> (Data, Int) {
        onRequest?(request)
        return try result.get()
    }
}

final class UpdateCheckTests: XCTestCase {
    private func body(_ tag: String, name: String = "Release", url: String = "https://github.com/bassmicrobe/alive-for-mac/releases/tag/x") -> Data {
        Data("{\"tag_name\":\"\(tag)\",\"name\":\"\(name)\",\"html_url\":\"\(url)\",\"body\":\"notes\"}".utf8)
    }

    // MARK: comparison

    func testCompareTable() {
        let table: [(String, String, UpdateCheck.Step)] = [
            ("0.1.0", "v0.2.0", .big),
            ("0.1.0", "0.1.1", .patch),
            ("0.1.0", "0.1.0", .none),
            ("0.1.0", "v0.1.0-mac1", .none),
            ("0.2.0", "0.1.9", .none),
            ("1.9", "1.10", .big),
            ("1.10", "1.9", .none),
            ("1.1", "1.1.0.0", .none),
            ("1.1", "1.1.0.1", .patch),
            ("0.2.0", "1.0.0", .big),
            ("v0.2.0", "V0.3.0+build5", .big),
            ("dev", "9.9.9", .none),
            ("0.1.0", "nightly", .none),
            ("0.1.0", "", .none),
            ("", "0.2.0", .none),
            ("0.1.0", "1.2.3.4.5", .none),
            ("0.1.0", "1..2", .none),
            ("0.1.0", "1.x", .none),
            ("0.1.0", "٣.0.0", .none),
        ]
        for (current, found, expected) in table {
            XCTAssertEqual(UpdateCheck.compare(current: current, found: found), expected,
                           "\(current) -> \(found)")
        }
    }

    func testParse() {
        XCTAssertEqual(UpdateCheck.parse("v0.2.0-mac1"), [0, 2, 0, 0])
        XCTAssertEqual(UpdateCheck.parse(" 12.4.5 "), [12, 4, 5, 0])
        XCTAssertNil(UpdateCheck.parse("v"))
        XCTAssertNil(UpdateCheck.parse("-1"))
        XCTAssertNil(UpdateCheck.parse("99999999999999999999.0"))
    }

    // MARK: answer

    func testNewerRelease() {
        let out = UpdateCheck.outcome(status: 200, body: body("v0.2.0", name: "Alive 0.2"), current: "0.1.0")
        guard case .newer(let r, let step) = out else { return XCTFail("\(out)") }
        XCTAssertEqual(step, .big)
        XCTAssertEqual(r.version, "0.2.0")
        XCTAssertEqual(r.name, "Alive 0.2")
        XCTAssertTrue(r.url.hasPrefix("https://github.com/"))
    }

    func testSameVersionIsUpToDate() {
        let out = UpdateCheck.outcome(status: 200, body: body("0.1.0"), current: "0.1.0")
        guard case .upToDate(let r) = out else { return XCTFail("\(out)") }
        XCTAssertEqual(r.version, "0.1.0")
    }

    func testUnbundledDevBuildIsNeverBehind() {
        let out = UpdateCheck.outcome(status: 200, body: body("v5.0.0"), current: "dev")
        guard case .upToDate = out else { return XCTFail("\(out)") }
    }

    func testStatuses() {
        XCTAssertEqual(UpdateCheck.outcome(status: 404, body: Data(), current: "0.1.0"), .noReleases)
        XCTAssertEqual(UpdateCheck.outcome(status: 403, body: Data(), current: "0.1.0"), .failed(.rateLimited))
        XCTAssertEqual(UpdateCheck.outcome(status: 429, body: Data(), current: "0.1.0"), .failed(.rateLimited))
        XCTAssertEqual(UpdateCheck.outcome(status: 500, body: Data(), current: "0.1.0"), .failed(.unreachable))
        XCTAssertEqual(UpdateCheck.outcome(status: 0, body: Data(), current: "0.1.0"), .failed(.unreachable))
    }

    func testGarbageBodies() {
        for garbage in ["", "not json", "[]", "{}", "{\"tag_name\":null}", "{\"tag_name\":\"\"}",
                        "{\"tag_name\":\"v\"}", "{\"tag_name\":42}", "<html>proxy login</html>"] {
            XCTAssertEqual(UpdateCheck.outcome(status: 200, body: Data(garbage.utf8), current: "0.1.0"),
                           .failed(.unexpectedAnswer), garbage)
        }
    }

    func testUnsafeLinkFallsBackToTheReleasesPage() {
        for url in ["javascript:alert(1)", "http://github.com/x", "https://evil.example/x", "file:///etc/passwd", ""] {
            let out = UpdateCheck.outcome(status: 200, body: body("9.0.0", url: url), current: "0.1.0")
            guard case .newer(let r, _) = out else { return XCTFail("\(out)") }
            XCTAssertEqual(r.url, UpdateCheck.pageURL, url)
        }
    }

    func testMissingLinkFallsBack() {
        let json = Data("{\"tag_name\":\"v9.0.0\"}".utf8)
        guard case .newer(let r, _) = UpdateCheck.outcome(status: 200, body: json, current: "0.1.0") else {
            return XCTFail()
        }
        XCTAssertEqual(r.url, UpdateCheck.pageURL)
        XCTAssertEqual(r.name, "")
    }

    // MARK: fetch

    func testFetchSendsAPlainGetAboutNobody() async {
        final class Box: @unchecked Sendable { var request: URLRequest? }
        let box = Box()
        var stub = StubFetcher(result: .success((body("v0.2.0"), 200)))
        stub.onRequest = { box.request = $0 }
        let out = await UpdateCheck.fetch(current: "0.1.0", using: stub)
        guard case .newer = out else { return XCTFail("\(out)") }

        let req = try? XCTUnwrap(box.request)
        XCTAssertEqual(req?.httpMethod, "GET")
        XCTAssertEqual(req?.url?.absoluteString, UpdateCheck.latestURL)
        XCTAssertTrue(UpdateCheck.latestURL.contains("bassmicrobe/alive-for-mac"))
        XCTAssertFalse(UpdateCheck.latestURL.contains("rueblose"))
        XCTAssertEqual(req?.value(forHTTPHeaderField: "User-Agent"), "AliveForMac/0.1.0")
        XCTAssertEqual(req?.timeoutInterval, UpdateCheck.timeout)
        XCTAssertNil(req?.httpBody)
        XCTAssertEqual(Set(req?.allHTTPHeaderFields?.keys.map { $0 } ?? []), ["User-Agent", "Accept"])
    }

    func testFetchMapsATimeoutAndOtherErrorsToUnreachable() async {
        for error in [URLError(.timedOut), URLError(.notConnectedToInternet), URLError(.cannotFindHost)] {
            let out = await UpdateCheck.fetch(current: "0.1.0", using: StubFetcher(result: .failure(error)))
            XCTAssertEqual(out, .failed(.unreachable))
        }
    }

    func testFetchNoReleasesYet() async {
        let out = await UpdateCheck.fetch(current: "0.1.0", using: StubFetcher(result: .success((Data("{}".utf8), 404))))
        XCTAssertEqual(out, .noReleases)
    }
}

final class UpdateScheduleTests: XCTestCase {
    func testDayKeyIsLocalAndPadded() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let date = DateComponents(calendar: cal, year: 2026, month: 3, day: 7, hour: 1).date!
        XCTAssertEqual(UpdateSchedule.dayKey(date, calendar: cal), "2026-03-07")
    }

    func testIsDue() {
        XCTAssertTrue(UpdateSchedule.isDue(enabled: true, lastCheck: "", today: "2026-03-07"))
        XCTAssertTrue(UpdateSchedule.isDue(enabled: true, lastCheck: "2026-03-06", today: "2026-03-07"))
        XCTAssertFalse(UpdateSchedule.isDue(enabled: true, lastCheck: "2026-03-07", today: "2026-03-07"))
        XCTAssertFalse(UpdateSchedule.isDue(enabled: false, lastCheck: "", today: "2026-03-07"))
    }

    func testDotOnlyForUnseenBigSteps() {
        let r = UpdateCheck.Release(version: "0.2.0")
        XCTAssertTrue(UpdateSchedule.shouldLightDot(.newer(r, step: .big), seen: ""))
        XCTAssertTrue(UpdateSchedule.shouldLightDot(.newer(r, step: .big), seen: "0.1.5"))
        XCTAssertFalse(UpdateSchedule.shouldLightDot(.newer(r, step: .big), seen: "0.2.0"))
        XCTAssertFalse(UpdateSchedule.shouldLightDot(.newer(r, step: .patch), seen: ""))
        XCTAssertFalse(UpdateSchedule.shouldLightDot(.upToDate(latest: r), seen: ""))
        XCTAssertFalse(UpdateSchedule.shouldLightDot(.noReleases, seen: ""))
        XCTAssertFalse(UpdateSchedule.shouldLightDot(.failed(.unreachable), seen: ""))
    }
}
