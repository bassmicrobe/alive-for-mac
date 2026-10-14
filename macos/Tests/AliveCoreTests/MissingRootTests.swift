import XCTest
@testable import AliveCore

final class MissingRootTests: XCTestCase {
    func testFolderScanTellsMissingFromUnreadable() throws {
        let t = makeTemp("missing-root")
        let gone = FolderScan.find(root: t.sub("moved"), ext: ".als", includeBackups: false, onFile: { _ in })
        XCTAssertTrue(gone.rootFailed)
        XCTAssertTrue(gone.rootMissing)

        let locked = t.mkdir("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked) }
        guard !FileManager.default.isReadableFile(atPath: locked) else { return }   // running as root
        let denied = FolderScan.find(root: locked, ext: ".als", includeBackups: false, onFile: { _ in })
        XCTAssertTrue(denied.rootFailed)
        XCTAssertFalse(denied.rootMissing)
    }

    func testScanStatsListMissingRootsButNotOfflineVolumes() {
        let t = makeTemp("missing-stats")
        let index = ProjectIndex(dir: t.sub("data"), home: t.mkdir("home"), applicationsDirs: [], settings: Settings())
        index.mountProvider = { ["Macintosh HD"] }
        let moved = t.sub("Dropbox/_sounds")
        let offline = "/Volumes/NoSuchDriveForAliveTests/Projects"
        let stats = index.scan(roots: [moved, offline], disabledRoots: [])
        XCTAssertEqual(Set(stats.failedRoots), [moved, offline])
        XCTAssertEqual(stats.missingRoots, [moved])
    }
}

final class ByteSizeTests: XCTestCase {
    func testFollowsTheGivenLocaleNotTheSystemOne() {
        let en = ByteSize.string(248, locale: Locale(identifier: "en_US"))
        let ja = ByteSize.string(248, locale: Locale(identifier: "ja_JP"))
        XCTAssertFalse(en.contains("バイト"), en)
        XCTAssertTrue(ja.contains("バイト"), ja)
        XCTAssertTrue(ByteSize.string(0, locale: Locale(identifier: "en_US")).hasPrefix("0"))
    }
}
