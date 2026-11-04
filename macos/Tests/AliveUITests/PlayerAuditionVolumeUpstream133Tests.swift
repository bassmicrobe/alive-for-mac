import XCTest
@testable import AliveUI

@MainActor
final class PlayerAuditionVolumeUpstream133Tests: XCTestCase {
    func testASoundCanStartAtItsOwnLevelWithoutMovingThePlayersVolume() throws {
        let t = makeHomeScratch()
        let audio = AudioPlayback()
        audio.volume = 0.9
        // Silent file at volume 0: nothing is audible, and a machine without audio output skips.
        guard audio.play(url: URL(fileURLWithPath: try t.writeWav("a.wav", seconds: 5)), volume: 0) else {
            throw XCTSkip("no audio device in this environment")
        }
        XCTAssertEqual(audio.player?.volume, 0, "this sound begins at its own level")
        XCTAssertEqual(audio.volume, 0.9, "the render player's level is untouched")
        audio.stop()
    }
}
