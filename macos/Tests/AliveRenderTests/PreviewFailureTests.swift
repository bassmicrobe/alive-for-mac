import XCTest
@testable import AliveCore
@testable import AliveRender

/// A set that cannot be read shows a typed, localized reason on the page; the parser's own
/// (English) diagnostics never reach it.
final class PreviewFailureTests: XCTestCase {
    private func load(_ bytes: Data, name: String = "Broken") throws -> PreviewModel {
        let dir = NSTemporaryDirectory() + "alive-ql-fail-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/\(name).als"
        try bytes.write(to: URL(fileURLWithPath: path))
        return PreviewModel.load(path: path)
    }

    func testAGarbageFileIsTypedAndWordedInTheChosenLanguage() throws {
        let model = try load(Data("definitely not a live set".utf8))
        let raw = try XCTUnwrap(model.info.error, "the core diagnostic is still there for the log")
        XCTAssertNotNil(model.failure)

        for language in [PreviewLanguage.en, .ja] {
            let html = PreviewPage.html(model, language: language, pictureSource: nil)
            XCTAssertTrue(html.contains(PreviewString.readFailed.text(language)))
            XCTAssertTrue(html.contains(model.shownFailure!.message.text(language)))
            XCTAssertFalse(html.contains(raw), "raw diagnostics must not appear on the page: \(raw)")
        }
    }

    func testAMissingFileIsCannotOpen() {
        let model = PreviewModel.load(path: "/nonexistent-\(UUID().uuidString)/x.als")
        XCTAssertEqual(model.failure, .cannotOpen)
        let html = PreviewPage.html(model, language: .ja, pictureSource: nil)
        XCTAssertTrue(html.contains(PreviewString.failCannotOpen.text(.ja)))
    }

    func testAReadableSetHasNoFailure() throws {
        let gz = try Gzip.compress(Data(SyntheticSet.xml().utf8))
        let model = try load(gz, name: "Fine")
        XCTAssertNil(model.failure)
        XCTAssertFalse(PreviewPage.html(model, language: .en, pictureSource: nil).contains("class=\"warn\""))
    }

    func testEveryFailureHasAMessage() {
        for failure in [PreviewFailure.cannotOpen, .notASet, .tooLarge, .damaged] {
            XCTAssertFalse(failure.message.text(.en).isEmpty)
            XCTAssertFalse(failure.message.text(.ja).isEmpty)
        }
    }
}
