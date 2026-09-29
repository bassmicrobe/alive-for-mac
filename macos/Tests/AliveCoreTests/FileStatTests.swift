// Mac-only: FileStat replaces FileManager.attributesOfItem in the scanners (see FileStat.swift).
import XCTest
@testable import AliveCore

final class FileStatTests: XCTestCase {
    private var dir = ""

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "filestat-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: dir)
    }

    func testReportsSizeAndTimesOfAFile() throws {
        let path = dir + "/a.bin"
        try Data(repeating: 7, count: 1234).write(to: URL(fileURLWithPath: path))
        let st = try XCTUnwrap(FileStat.of(path))
        XCTAssertEqual(st.size, 1234)
        XCTAssertFalse(st.isDirectory)
        XCTAssertLessThan(abs(st.modified.timeIntervalSinceNow), 60)
        XCTAssertLessThan(abs(st.created.timeIntervalSinceNow), 60)
        XCTAssertEqual(FileStat.size(of: path), 1234)
    }

    func testDirectoryAndMissingPath() {
        XCTAssertEqual(FileStat.of(dir)?.isDirectory, true)
        XCTAssertNil(FileStat.of(dir + "/nope"))
        XCTAssertEqual(FileStat.size(of: dir + "/nope"), 0)
    }
}
