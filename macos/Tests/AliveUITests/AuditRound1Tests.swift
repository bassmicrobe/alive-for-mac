import CoreGraphics
import XCTest
@testable import AliveCore
@testable import AliveRender
@testable import AliveUI

/// The first audit round: one test for each thing that was wrong.
@MainActor
final class AuditRound1Tests: XCTestCase {
    // 4. settings.cfg that could not be read at start is read again by the next change.
    func testASettingsChangeReadsAnUnreadSettingsFileAgainAndKeepsItsContent() throws {
        try XCTSkipIf(geteuid() == 0, "root can read anything")
        let app0Dir = NSTemporaryDirectory() + "alive-audit-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: app0Dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: app0Dir) }
        let cfg = app0Dir + "/settings.cfg"
        try "root=/precious\n".write(toFile: cfg, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: cfg)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cfg) }

        let app = AppModel(dataDir: app0Dir)
        XCTAssertTrue(app.settings.isUnread)
        app.mutateSettings { $0.spotlight = false }
        XCTAssertTrue(app.settings.isUnread, "still unreadable: nothing is written")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cfg)
        app.mutateSettings { $0.menuBar = false }
        XCTAssertFalse(app.settings.isUnread)
        let saved = try String(contentsOfFile: cfg, encoding: .utf8)
        XCTAssertTrue(saved.contains("root=/precious"), saved)
        XCTAssertTrue(saved.contains("menubar=0"), saved)
    }

    // 6. A long loop shows its notes wherever the view is, not only in the first 512 repetitions.
    func testLoopedNotesFarIntoALongClipAreDrawn() throws {
        var clip = ClipBlock()
        clip.start = 0; clip.end = 2400
        clip.isMidi = true
        clip.loopStart = 0; clip.loopEnd = 4; clip.loopOn = true
        clip.notes = [NoteEvent(time: 1, duration: 1, pitch: 60, velocity: 100)]
        clip.minPitch = 60; clip.maxPitch = 60
        let g = try XCTUnwrap(CGContext(data: nil, width: 1000, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // 10 px a beat, scrolled to beats 2100...2200 (the old 512 repetitions end at beat 2048).
        let plot = CGRect(x: 0, y: 0, width: 1000, height: 20)
        let drawn = ArrangementRender.drawNotes(g, rect: plot, origin: -21_000, plot: plot, clip: clip,
                                                color: RGBColor(hex: 0xFFFFFF), pxPerBeat: 10, alpha: 255)
        XCTAssertEqual(drawn, 25)

        let reps = ArrangementRender.visibleRepeats(clip: clip, noteStart: 1, noteEnd: 2, fromBeat: 2100, toBeat: 2200)
        XCTAssertGreaterThan(reps.lowerBound, 500, "the repetitions before the view are not visited")
        XCTAssertLessThan(reps.count, 60)
    }

    // 7. At 125 % the window may not ask for more than the screen has.
    func testTheMainWindowMinimumIsCappedToTheScreen() {
        let roomy = MainWindowSize.make(uiScale: 125, screen: CGSize(width: 2560, height: 1400))
        XCTAssertEqual(roomy.minimum, CGSize(width: 1400, height: 750))
        XCTAssertEqual(roomy.ideal, CGSize(width: 1550, height: 975))

        let small = MainWindowSize.make(uiScale: 125, screen: CGSize(width: 1280, height: 695))
        XCTAssertEqual(small.minimum, CGSize(width: 1280, height: 695))
        XCTAssertEqual(small.ideal, CGSize(width: 1280, height: 695))
    }

    // 8. Down in the search field on the Samples tab picks the first row and asks the list for focus.
    func testDownFromSearchOnTheSamplesTabPicksTheFirstRowAndFocusesTheList() async throws {
        let base = NSTemporaryDirectory() + "alive-audit-samples-" + UUID().uuidString
        addTeardownBlock { try? FileManager.default.removeItem(atPath: base) }
        try FileManager.default.createDirectory(atPath: base + "/data", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: base + "/Lib", withIntermediateDirectories: true)
        for name in ["kick.wav", "snare.wav"] {
            try Self.silentWav().write(to: URL(fileURLWithPath: base + "/Lib/" + name))
        }
        let app = AppModel(dataDir: base + "/data")
        app.audio.volume = 0
        app.mutateSettings { $0.sampleRoots = [base + "/Lib"] }
        let m = app.samples
        m.start()
        await m.loadTask?.value
        await m.scanTask?.value
        await m.settle()

        app.tab = .samples
        XCTAssertNil(m.selection)
        let before = m.listFocusRequest
        app.focusResults()
        XCTAssertEqual(m.selection, m.listing.rows.first?.id)
        XCTAssertNotNil(m.selection)
        XCTAssertEqual(m.listFocusRequest, before + 1)
    }

    private static func silentWav() -> Data {
        func le(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        let bytes = 4410 * 2
        var d = Array("RIFF".utf8) + le(36 + bytes, 4) + Array("WAVE".utf8) + Array("fmt ".utf8) + le(16, 4)
        d += le(1, 2) + le(1, 2) + le(44100, 4) + le(88200, 4) + le(2, 2) + le(16, 2)
        d += Array("data".utf8) + le(bytes, 4) + [UInt8](repeating: 0, count: bytes)
        return Data(d)
    }
}
