import CoreGraphics
import XCTest
@testable import AliveCore
@testable import AliveRender
@testable import AliveUI

/// The second audit round: one test for each thing that was wrong.
@MainActor
final class AuditRound2Tests: XCTestCase {
    private func scratch() throws -> String {
        let dir = NSTemporaryDirectory() + "alive-audit2-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    /// Takes all permissions from `path` until the test ends.
    private func lock(_ path: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }
    }

    /// A silent 16-bit mono WAV of `frames` frames.
    private func wav(frames: Int) -> Data {
        func le(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        var d = Array("RIFF".utf8) + le(36 + frames * 2, 4) + Array("WAVE".utf8) + Array("fmt ".utf8) + le(16, 4)
        d += le(1, 2) + le(1, 2) + le(44100, 4) + le(88200, 4) + le(2, 2) + le(16, 2)
        d += Array("data".utf8) + le(frames * 2, 4) + [UInt8](repeating: 0, count: frames * 2)
        return Data(d)
    }

    // SR1. A data file that cannot be read is announced once at launch, through the stores the app
    // writes with, and a later change to it does not toast again.
    func testUnreadDataFilesAreAnnouncedOnceThroughTheStoresTheAppUses() throws {
        try XCTSkipIf(geteuid() == 0, "root can read anything")
        let dir = try scratch()
        for name in ["notes.cfg", "home.cfg"] {
            try "x\n".write(toFile: dir + "/" + name, atomically: true, encoding: .utf8)
            try lock(dir + "/" + name)
        }
        let app = AppModel(dataDir: dir)

        app.announceUnreadFiles()
        XCTAssertEqual(app.toasts.count, 1)
        let text = try XCTUnwrap(app.toasts.first?.text)
        XCTAssertTrue(text.contains("notes.cfg") && text.contains("home.cfg"), text)
        XCTAssertFalse(text.contains("previews.cfg") || text.contains("settings.cfg"), text)

        app.home.togglePin(path: "/a/One.als")
        XCTAssertEqual(app.toasts.count, 1, "home.cfg was already announced")
    }

    // 9. Without a log nothing is revealed and the toast does not point at "alive.log".
    func testAnExportWithoutALogDoesNotSendThePersonToIt() {
        let withLog = ExportModel.failureOutcome(name: "Song", failed: 2, logPath: "/data/alive.log")
        XCTAssertEqual(withLog.reveal, "/data/alive.log")
        XCTAssertEqual(withLog.text, ExportStrings.toastDoneWithFailures.f("Song", ExportStrings.files(2)))

        let noLog = ExportModel.failureOutcome(name: "Song", failed: 2, logPath: nil)
        XCTAssertNil(noLog.reveal)
        XCTAssertEqual(noLog.text, ExportStrings.toastDoneWithFailuresNoLog.f("Song", ExportStrings.files(2)))
    }

    // 10a. nebula.cfg that cannot be read is not written over with the defaults.
    func testNebulaCfgThatCannotBeReadIsNotOverwritten() throws {
        try XCTSkipIf(geteuid() == 0, "root can read anything")
        let app = try makeModel(files: ["nebula.cfg": "x=bpm\nspin=1\n"])
        let cfg = app.dataDir + "/nebula.cfg"
        try lock(cfg)
        let stat = app.stat
        XCTAssertTrue(stat.config.isUnread)

        stat.setSpin(false)
        stat.saveNow()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cfg)
        XCTAssertEqual(try String(contentsOfFile: cfg, encoding: .utf8), "x=bpm\nspin=1\n")
    }

    // SR6. A version folded under its folder's tile is still the selection when Home shows.
    func testASelectedOlderVersionStaysSelectedWhileItsFolderHasATile() {
        func set(_ path: String) -> SetEntry { var s = SetEntry(); s.path = path; return s }
        let newest = set("/M/A Project/new.als"), older = set("/M/A Project/old.als"), other = set("/M/B Project/b.als")
        let all = [newest, older, other]

        XCTAssertEqual(HomeSelection.keptIncludingFolded(older.path, in: [newest], sets: all), older.path)
        XCTAssertNil(HomeSelection.keptIncludingFolded(other.path, in: [newest], sets: all), "its folder has no tile")
        XCTAssertNil(HomeSelection.keptIncludingFolded(nil, in: [newest], sets: all))
    }

    // SR8. The same part of the song stays in view when the window moves to a screen of another density.
    func testTheViewportKeepsItsPlaceWhenThePixelDensityChanges() {
        func space(scale: Double) -> ArrangementSpace {
            ArrangementSpace(area: CGRect(x: 0, y: 0, width: 1000 * scale, height: 300 * scale), trackCount: 10, end: 64,
                             options: .preview(scale: scale))
        }
        let one = space(scale: 1), two = space(scale: 2)
        var v = ArrangementViewport()
        v.ensure(in: one)
        v.zoom(factor: 4, atX: one.plot.midX, in: one)
        v.scroll(toX: 100, y: 0, in: one)
        let beatAtLeft = v.scrollX / v.pxPerBeat
        let zoom = v.zoomFactor(in: one)

        v.ensure(in: two)
        XCTAssertEqual(v.scrollX / v.pxPerBeat, beatAtLeft, accuracy: 1e-9, "the same beat is at the left edge")
        XCTAssertEqual(v.zoomFactor(in: two), zoom, accuracy: 0.05, "and the same zoom")
    }

    // SR5. ⌘R before the tab has started walks even when the cache says it is fresh.
    func testARescanBeforeTheSamplesTabStartedWalksEvenWithAFreshCache() async throws {
        let base = try scratch()
        try FileManager.default.createDirectory(atPath: base + "/data", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: base + "/Lib", withIntermediateDirectories: true)
        try wav(frames: 4410).write(to: URL(fileURLWithPath: base + "/Lib/kick.wav"))
        let first = AppModel(dataDir: base + "/data")
        first.mutateSettings { $0.sampleRoots = [base + "/Lib"] }
        first.samples.start()
        await first.samples.loadTask?.value
        await first.samples.scanTask?.value
        XCTAssertEqual(first.samples.index.totalSamples, 1)

        try wav(frames: 4410).write(to: URL(fileURLWithPath: base + "/Lib/snare.wav"))
        let second = AppModel(dataDir: base + "/data")
        second.mutateSettings { $0.sampleRoots = [base + "/Lib"] }
        second.samples.rescan()
        await second.samples.loadTask?.value
        await second.samples.scanTask?.value
        XCTAssertEqual(second.samples.index.totalSamples, 2)
    }
}
