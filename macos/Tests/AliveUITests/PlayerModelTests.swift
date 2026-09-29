import XCTest
@testable import AliveCore
@testable import AliveUI

/// None of these tests plays anything: renders are only listed, selected and decoded for peaks.
@MainActor
final class PlayerModelTests: XCTestCase {
    /// Models hold `app` unowned: keep the apps alive for the whole test.
    private var apps: [AppModel] = []

    private func makePlayer(_ scratch: HomeScratch) -> (AppModel, PlayerModel) {
        let app = AppModel(dataDir: scratch.sub("data"))
        apps.append(app)
        app.audio.volume = 0
        app.player.systemMediaEnabled = false
        return (app, app.player)
    }

    /// A project folder with a set and two renders; the older one is the pinned candidate.
    private func makeProject(_ scratch: HomeScratch) throws -> (set: String, newer: String, older: String) {
        let set = try scratch.writeSet("Songs/Night Project/night.als")
        let older = try scratch.writeWav("Songs/Night Project/Renders/old mix.wav")
        let newer = try scratch.writeWav("Songs/Night Project/Renders/new mix.wav")
        scratch.setModified(older, Date(timeIntervalSince1970: 1_700_000_000))
        scratch.setModified(newer, Date(timeIntervalSince1970: 1_800_000_000))
        // Samples never count as renders.
        _ = try scratch.writeWav("Songs/Night Project/Samples/Recorded/take.wav")
        return (set, newer, older)
    }

    private func waitForWaveform(_ player: PlayerModel) async {
        for _ in 0..<200 where player.waveform == nil { try? await Task.sleep(nanoseconds: 25_000_000) }
    }

    func testLoadListsRendersNewestFirstAndSelectsTheBestWithoutPlaying() async throws {
        let scratch = makeHomeScratch()
        let (app, player) = makePlayer(scratch)
        let p = try makeProject(scratch)

        await player.load(setAt: p.set, autoStart: false)
        XCTAssertEqual(player.setPath, p.set)
        XCTAssertEqual(player.setName, "night")
        XCTAssertEqual(player.files.map(\.name), ["new mix", "old mix"], "Samples are skipped, newest first")
        XCTAssertEqual(player.currentIndex, 0)
        XCTAssertEqual(player.currentFile?.path, p.newer)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isCurrentOpen, "loading with autoStart false opens nothing")
        XCTAssertNil(app.audio.url)
        XCTAssertFalse(player.isStripVisible, "the Home strip only shows once something was played")
        await waitForWaveform(player)
        XCTAssertEqual(player.waveform?.ok, true)
        XCTAssertNil(player.note)
    }

    func testSetWithoutRendersSaysSo() async throws {
        let scratch = makeHomeScratch()
        let (_, player) = makePlayer(scratch)
        let set = try scratch.writeSet("Songs/Quiet Project/quiet.als")
        await player.load(setAt: set, autoStart: false)
        XCTAssertTrue(player.files.isEmpty)
        XCTAssertNil(player.currentFile)
        XCTAssertEqual(player.note, HomeStrings.noRenders.s)
        XCTAssertEqual(player.duration, 0)
    }

    func testPinnedRenderComesFirstAndSurvivesRefresh() async throws {
        let scratch = makeHomeScratch()
        let (_, player) = makePlayer(scratch)
        let p = try makeProject(scratch)
        await player.load(setAt: p.set, autoStart: false)
        let old = try XCTUnwrap(player.files.last)
        await player.togglePin(old)
        XCTAssertEqual(player.files.first?.path, p.older)
        XCTAssertEqual(player.files.first?.pinned, true)
        XCTAssertEqual(player.currentFile?.path, p.newer, "the current render is found again after the reorder")
        // Persisted in previews.cfg like upstream, so a fresh model picks it up.
        let (_, other) = makePlayer(scratch)
        await other.load(setAt: p.set, autoStart: false)
        XCTAssertEqual(other.currentFile?.path, p.older)
        await player.togglePin(try XCTUnwrap(player.files.first))
        XCTAssertEqual(player.files.first?.path, p.newer, "clearing the pin restores date order")
    }

    func testSeekBeforePlayIsKeptAndStepFileMovesTheSelection() async throws {
        let scratch = makeHomeScratch()
        let (_, player) = makePlayer(scratch)
        let p = try makeProject(scratch)
        await player.load(setAt: p.set, autoStart: false)
        player.seek(toFraction: 0.25)
        XCTAssertEqual(player.progress, 0.25, accuracy: 0.0001)
        player.seek(toFraction: 7)
        XCTAssertEqual(player.progress, 1)
        XCTAssertFalse(player.stepFile(-1, autoStart: false), "already on the first render")
        XCTAssertTrue(player.stepFile(+1, autoStart: false))
        XCTAssertEqual(player.currentFile?.path, p.older)
        XCTAssertEqual(player.progress, 0, "a new render starts from the beginning")
        XCTAssertFalse(player.stepFile(+1, autoStart: false), "no render after the last")
        XCTAssertFalse(player.isPlaying)
    }

    func testMediaKeysThatNeedNoSoundAreHarmless() async throws {
        let scratch = makeHomeScratch()
        let (app, player) = makePlayer(scratch)
        player.apply(.pause)
        player.apply(.stop)
        player.apply(.next)
        XCTAssertNil(player.setPath)
        XCTAssertNil(app.audio.url)
    }

    func testUnloadForgetsTheSet() async throws {
        let scratch = makeHomeScratch()
        let (_, player) = makePlayer(scratch)
        let p = try makeProject(scratch)
        await player.load(setAt: p.set, autoStart: false)
        player.unload()
        XCTAssertNil(player.setPath)
        XCTAssertTrue(player.files.isEmpty)
        XCTAssertNil(player.currentFile)
        XCTAssertNil(player.waveform)
    }

    func testLoadingAnotherSetReplacesTheList() async throws {
        let scratch = makeHomeScratch()
        let (_, player) = makePlayer(scratch)
        let p = try makeProject(scratch)
        let other = try scratch.writeSet("Songs/Day Project/day.als")
        _ = try scratch.writeWav("Songs/Day Project/day mix.wav")
        await player.load(setAt: p.set, autoStart: false)
        await player.load(setAt: other, autoStart: false)
        XCTAssertEqual(player.files.map(\.name), ["day mix"])
        XCTAssertEqual(player.setName, "day")
    }

    // MARK: pure helpers

    func testNeighbourSkipsSetsWithoutRendersAndNeverReturnsItself() {
        func entry(_ name: String, renders: Bool) -> SetEntry {
            var e = SetEntry(); e.path = "/\(name).als"; e.hasRenders = renders; return e
        }
        let list = [entry("a", renders: true), entry("b", renders: false), entry("c", renders: true), entry("d", renders: true)]
        XCTAssertEqual(PlayerModel.neighbour(of: "/a.als", in: list, delta: +1), "/c.als")
        XCTAssertEqual(PlayerModel.neighbour(of: "/c.als", in: list, delta: -1), "/a.als")
        XCTAssertEqual(PlayerModel.neighbour(of: "/a.als", in: list, delta: -1), "/d.als", "wraps around")
        XCTAssertNil(PlayerModel.neighbour(of: "/a.als", in: [list[0]], delta: +1), "a list of one never loops onto itself")
        XCTAssertEqual(PlayerModel.neighbour(of: nil, in: list, delta: +1), "/a.als")
        XCTAssertNil(PlayerModel.neighbour(of: "/a.als", in: [], delta: +1))
    }

    func testTimeFormatting() {
        XCTAssertEqual(PlayerFormat.time(0), "0:00")
        XCTAssertEqual(PlayerFormat.time(7.9), "0:07")
        XCTAssertEqual(PlayerFormat.time(156), "2:36")
        XCTAssertEqual(PlayerFormat.time(3723), "1:02:03")
        XCTAssertEqual(PlayerFormat.time(-4), "0:00")
    }
}

final class PlayerWaveformTests: XCTestCase {
    func testSilentWavGivesAFlatEnvelopeOfTheRightLength() throws {
        let scratch = makeHomeScratch()
        let path = try scratch.writeWav("silent.wav", seconds: 2, rate: 8000)
        let wave = WaveformReader.read(path: path, buckets: 100)
        XCTAssertTrue(wave.ok)
        XCTAssertEqual(wave.buckets, 100)
        XCTAssertEqual(wave.min.count, 100)
        XCTAssertEqual(wave.duration, 2, accuracy: 0.01)
        XCTAssertEqual(wave.max.max() ?? 1, 0, accuracy: 0.0001)
        XCTAssertEqual(wave.min.min() ?? -1, 0, accuracy: 0.0001)
    }

    func testLoudPartsShowInTheEnvelope() throws {
        let scratch = makeHomeScratch()
        let path = try scratch.writeWav("loud.wav", seconds: 1, rate: 8000, amplitude: 0.8)
        let wave = WaveformReader.read(path: path, buckets: 50)
        XCTAssertTrue(wave.ok)
        XCTAssertGreaterThan(wave.max.max() ?? 0, 0.6)
        XCTAssertLessThan(wave.min.min() ?? 0, -0.6)
        XCTAssertTrue(zip(wave.min, wave.max).allSatisfy { $0 <= $1 })
    }

    func testFewBucketsAreRaisedToTheMinimum() throws {
        let path = try makeHomeScratch().writeWav("a.wav")
        XCTAssertEqual(WaveformReader.read(path: path, buckets: 1).buckets, WaveformReader.minBuckets)
    }

    func testUnreadableFileFails() {
        let scratch = makeHomeScratch()
        XCTAssertFalse(WaveformReader.read(path: scratch.sub("missing.wav"), buckets: 64).ok)
        let junk = scratch.write("junk.wav", "this is not audio")
        XCTAssertFalse(WaveformReader.read(path: junk, buckets: 64).ok)
    }

    func testCancellationStopsTheRead() throws {
        let path = try makeHomeScratch().writeWav("long.wav", seconds: 20)
        XCTAssertFalse(WaveformReader.read(path: path, buckets: 64, isCancelled: { true }).ok)
    }
}
