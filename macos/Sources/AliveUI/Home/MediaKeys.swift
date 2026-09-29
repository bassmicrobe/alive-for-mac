// Port of src/MediaKeys.cs. Windows sends media keys to the focused window as WM_APPCOMMAND; on the
// Mac they arrive through MPRemoteCommandCenter (keyboard keys, headphones, Control Centre) and the
// same registration fills the Now Playing widget. Registered only while a render is loaded, so an
// idle Alive never takes the keys away from Music or a browser.
import Foundation
import MediaPlayer

@MainActor
final class MediaKeys {
    /// The commands upstream understands (`MediaKeys.Cmd`).
    enum Command: Equatable {
        case playPause, play, pause, stop, next, previous
    }

    /// What Now Playing shows.
    struct Info: Equatable {
        var title: String
        var artist: String
        var elapsed: TimeInterval
        var duration: TimeInterval
        var isPlaying: Bool
    }

    private let handler: (Command) -> Void
    private var tokens: [(MPRemoteCommand, Any)] = []
    private(set) var isActive = false

    init(handler: @escaping (Command) -> Void) {
        self.handler = handler
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand, .play)
        register(center.pauseCommand, .pause)
        register(center.togglePlayPauseCommand, .playPause)
        register(center.stopCommand, .stop)
        register(center.nextTrackCommand, .next)
        register(center.previousTrackCommand, .previous)
        let seek = center.changePlaybackPositionCommand
        seek.isEnabled = false
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        for (command, token) in tokens { command.removeTarget(token) }
        tokens.removeAll()
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = nil
        info.playbackState = .stopped
    }

    func update(_ info: Info) {
        guard isActive else { return }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyArtist: info.artist,
            MPMediaItemPropertyPlaybackDuration: info.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? 1.0 : 0.0,
        ]
        center.playbackState = info.isPlaying ? .playing : .paused
    }

    private func register(_ command: MPRemoteCommand, _ mapped: Command) {
        command.isEnabled = true
        let handler = self.handler
        // Handlers may be called off the main thread; the model lives on it.
        let token = command.addTarget { _ in
            Task { @MainActor in handler(mapped) }
            return .success
        }
        tokens.append((command, token))
    }
}
