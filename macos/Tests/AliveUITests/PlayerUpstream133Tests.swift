import XCTest
@testable import AliveCore
@testable import AliveUI

/// Upstream 9ce4b4b / 0bb4915 in the player: a wave that survives a cut-short file, and the
/// render Shift+Return shows in Finder. Nothing is played.
@MainActor
final class PlayerUpstream133Tests: XCTestCase {
    private var apps: [AppModel] = []

    /// A 16-bit mono WAV whose header claims `claimed` frames of a loud tone while the file holds only `held`.
    private func cutShortWav(_ dir: String, claimed: Int, held: Int) throws -> String {
        func le(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        var bytes = Array("RIFF".utf8) + le(36 + claimed * 2, 4) + Array("WAVE".utf8) + Array("fmt ".utf8) + le(16, 4)
        bytes += le(1, 2) + le(1, 2) + le(8000, 4) + le(16_000, 4) + le(2, 2) + le(16, 2)
        bytes += Array("data".utf8) + le(claimed * 2, 4)
        for i in 0..<held { bytes += le(Int(UInt16(bitPattern: Int16(20_000 * sin(Double(i) * 0.05)))), 2) }
        let path = dir + "/cut.wav"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try Data(bytes).write(to: URL(fileURLWithPath: path))
        return path
    }

    func testAWavCutShortMidReadStillGivesAnEnvelope() throws {
        let scratch = makeHomeScratch()
        let path = try cutShortWav(scratch.sub("wave"), claimed: 8000, held: 2000)
        let wave = WaveformReader.read(path: path, buckets: 64)
        XCTAssertTrue(wave.ok, "what is there is shown")
        XCTAssertEqual(wave.buckets, 64)
        XCTAssertEqual(wave.duration, 0.25, accuracy: 0.01, "the length is what the file holds, not what its header claims")
        XCTAssertGreaterThan(wave.max.prefix(8).max() ?? 0, 0.3, "the part that exists is drawn")
        XCTAssertGreaterThan(wave.max.suffix(8).max() ?? 0, 0.3, "…across the whole picture")
    }

    func testAFileThatCannotBeReadLeavesALineInTheLogAndNoWave() throws {
        let scratch = makeHomeScratch()
        Diag.start(dir: scratch.sub("data"))
        defer { Diag.stop() }
        let path = scratch.write("junk/broken.wav", "this is not audio")
        XCTAssertFalse(WaveformReader.read(path: path, buckets: 64).ok)
        let log = try String(contentsOfFile: Diag.defaultLogPath(dir: scratch.sub("data")), encoding: .utf8)
        XCTAssertTrue(log.contains("wave: " + path), "the failure is logged with the file")
    }

    func testShiftReturnRevealsTheSelectedRenderElseTheOneInTheWindow() async throws {
        let scratch = makeHomeScratch()
        let app = AppModel(dataDir: scratch.sub("data"))
        apps.append(app)
        app.audio.volume = 0
        app.player.systemMediaEnabled = false
        let set = try scratch.writeSet("Songs/Night/night.als")
        let older = try scratch.writeWav("Songs/Night/Renders/old.wav")
        let newer = try scratch.writeWav("Songs/Night/Renders/new.wav")
        scratch.setModified(older, Date(timeIntervalSince1970: 1_700_000_000))
        scratch.setModified(newer, Date(timeIntervalSince1970: 1_800_000_000))
        await app.player.load(setAt: set, autoStart: false)

        XCTAssertEqual(app.player.renderToReveal(selectedID: older)?.path, older, "the row that is selected")
        XCTAssertEqual(app.player.renderToReveal(selectedID: nil)?.path, newer, "none selected: the current render")
        XCTAssertEqual(app.player.renderToReveal(selectedID: "/gone.wav")?.path, newer, "a stale selection falls back too")
    }
}
