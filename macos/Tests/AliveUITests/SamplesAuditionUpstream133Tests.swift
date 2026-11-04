import XCTest
@testable import AliveCore
@testable import AliveUI

/// The audition changes of upstream a6c8dc1: the volume under the wave, → and a press on nothing.
/// The samples are silent files, so nothing here is heard whatever the volume.
@MainActor
final class SamplesAuditionUpstream133Tests: XCTestCase {
    /// An app model on a scratch data folder with one sample folder (`Lib/Drums/kick.wav`), walked.
    private func startedModel() async throws -> (AppModel, SamplesModel, path: String) {
        let scratch = makeHomeScratch()
        let wav = try scratch.writeWav("Lib/Drums/kick.wav", seconds: 2)
        try scratch.writeWav("Lib/Drums/snare.wav", seconds: 2)
        let app = AppModel(dataDir: scratch.sub("data"))
        app.mutateSettings { $0.sampleRoots = [scratch.sub("Lib")] }
        let m = app.samples
        m.start()
        await m.loadTask?.value
        await m.scanTask?.value
        await m.settle()
        return (app, m, SampleIndex.norm(wav))
    }

    func testPreviewVolumeIsClampedAndRememberedInSettings() async throws {
        let (app, m, _) = try await startedModel()
        XCTAssertEqual(m.previewVolume, 0.8, "upstream's default")

        m.setPreviewVolume(1.7)
        XCTAssertEqual(m.previewVolume, 1)
        m.setPreviewVolume(-3)
        XCTAssertEqual(m.previewVolume, 0)
        m.setPreviewVolume(0.35)
        m.flushPreviewVolume()

        XCTAssertEqual(Settings.load(dir: app.dataDir).previewVolume, 0.35, accuracy: 0.001)
        XCTAssertEqual(AppModel(dataDir: app.dataDir).samples.previewVolume, 0.35, accuracy: 0.001,
                       "the next run starts where the slider was left")
    }

    func testPreviewVolumeReachesTheSampleAndNeverTheRenderPlayer() async throws {
        let (app, m, path) = try await startedModel()
        app.audio.volume = 0.5                               // the render player's own level
        m.setPreviewVolume(0.2)
        m.select(path)
        XCTAssertTrue(m.playSelectedFromStart())
        try XCTSkipIf(app.audio.url == nil, "no audio output on this machine")
        XCTAssertEqual(try XCTUnwrap(app.audio.player).volume, 0.2, accuracy: 0.001)

        m.setPreviewVolume(0.6)                              // moved while it plays: heard at once
        XCTAssertEqual(try XCTUnwrap(app.audio.player).volume, 0.6, accuracy: 0.001)
        XCTAssertEqual(app.audio.volume, 0.5, "the render player's level is not the slider's")

        let render = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent + "/snare.wav")  // a render takes over
        XCTAssertTrue(app.audio.play(url: render))
        m.setPreviewVolume(0.9)
        XCTAssertEqual(try XCTUnwrap(app.audio.player).volume, 0.5, accuracy: 0.001,
                       "the slider does not reach a sound this tab did not start")
        app.audio.stop()
    }

    func testRightArrowPlaysTheSelectedSampleFromTheStartAndLeavesFoldersToTheTree() async throws {
        let (app, m, path) = try await startedModel()
        XCTAssertFalse(m.playSelectedFromStart(), "nothing selected: → is the tree's")
        m.select(SampleIndex.norm((path as NSString).deletingLastPathComponent))
        XCTAssertFalse(m.playSelectedFromStart(), "a folder: → opens it")

        m.select(path)
        XCTAssertTrue(m.playSelectedFromStart())
        try XCTSkipIf(app.audio.url == nil, "no audio output on this machine")
        app.audio.seek(to: 1.5)
        XCTAssertTrue(m.playSelectedFromStart())
        XCTAssertLessThan(app.audio.currentTime, 0.5, "again from the start, not from where it was")
        app.audio.stop()
    }

    func testAPressOnNothingStopsTheSample() async throws {
        let (app, m, path) = try await startedModel()
        m.select(path)
        XCTAssertTrue(m.playSelectedFromStart())
        try XCTSkipIf(app.audio.url == nil, "no audio output on this machine")
        m.emptyClicked()
        XCTAssertNil(app.audio.url)
    }
}
