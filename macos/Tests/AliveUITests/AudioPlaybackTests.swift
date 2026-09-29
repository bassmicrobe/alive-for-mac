import AVFoundation
import XCTest
@testable import AliveUI

@MainActor
final class AudioPlaybackTests: XCTestCase {
    /// A player that is never started.
    private func idlePlayer(_ scratch: HomeScratch, _ name: String) throws -> AVAudioPlayer {
        try AVAudioPlayer(contentsOf: URL(fileURLWithPath: try scratch.writeWav(name)))
    }

    func testCallbacksOfAPlayerThatIsNotCurrentAreIgnored() throws {
        let t = makeHomeScratch()
        let audio = AudioPlayback()
        var finished = 0, errors = 0
        audio.onFinished = { finished += 1 }
        audio.onError = { _ in errors += 1 }
        let stranger = try idlePlayer(t, "a.wav")
        audio.handleFinished(from: stranger)
        audio.handleDecodeError(from: stranger, error: nil)
        XCTAssertEqual(finished, 0)
        XCTAssertEqual(errors, 0)
    }

    func testLateCallbackOfAReplacedTrackDoesNotEndTheNewOne() throws {
        let t = makeHomeScratch()
        let audio = AudioPlayback()
        audio.volume = 0                       // silent file, muted: nothing is audible
        var finished = 0, errors = 0
        audio.onFinished = { finished += 1 }
        audio.onError = { _ in errors += 1 }
        guard audio.play(url: URL(fileURLWithPath: try t.writeWav("a.wav", seconds: 5))) else {
            throw XCTSkip("no audio device in this environment")
        }
        let first = try XCTUnwrap(audio.player)
        guard audio.play(url: URL(fileURLWithPath: try t.writeWav("b.wav", seconds: 5))) else {
            throw XCTSkip("no audio device in this environment")
        }
        audio.handleFinished(from: first)
        XCTAssertEqual(finished, 0)
        XCTAssertTrue(audio.isPlaying)

        audio.handleDecodeError(from: try XCTUnwrap(audio.player), error: nil)
        XCTAssertEqual(errors, 1)
        XCTAssertFalse(audio.isPlaying)
        XCTAssertNil(audio.player)
        audio.stop()
    }
}
