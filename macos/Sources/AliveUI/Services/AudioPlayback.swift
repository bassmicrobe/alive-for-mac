// Mac-only: replaces upstream's Media Foundation / waveOut playback. One wrapper used by the
// player window *and* sample audition (each owner creates its own instance).
import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class AudioPlayback {
    private(set) var url: URL?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var volume: Float = 1 {
        didSet { player?.volume = volume }
    }

    /// Called when playback reaches the end of the file.
    @ObservationIgnored var onFinished: (() -> Void)?
    /// Called with the underlying error when a file cannot be opened or played.
    @ObservationIgnored var onError: ((Error) -> Void)?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var delegate: Delegate?

    deinit { timer?.invalidate() }

    /// Starts playing `url` from the beginning. Returns false (after reporting via `onError`)
    /// when the file cannot be played.
    @discardableResult
    func play(url: URL) -> Bool {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = Delegate { [weak self] in self?.didFinish() }
            player.delegate = delegate
            player.volume = volume
            guard player.play() else { throw PlaybackError.couldNotStart }
            self.player = player
            self.delegate = delegate
            self.url = url
            duration = player.duration
            currentTime = 0
            isPlaying = true
            startTimer()
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    func pause() {
        guard let player, isPlaying else { return }
        player.pause()
        isPlaying = false
        stopTimer()
        currentTime = player.currentTime
    }

    func resume() {
        guard let player, !isPlaying else { return }
        guard player.play() else {
            onError?(PlaybackError.couldNotStart)
            return
        }
        isPlaying = true
        startTimer()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        delegate = nil
        url = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, time), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    // MARK: - Internals

    enum PlaybackError: Error { case couldNotStart }

    private func didFinish() {
        stopTimer()
        isPlaying = false
        currentTime = duration
        onFinished?()
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private final class Delegate: NSObject, AVAudioPlayerDelegate {
        private let finished: @MainActor () -> Void

        init(finished: @escaping @MainActor () -> Void) {
            self.finished = finished
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            Task { @MainActor in finished() }
        }
    }
}
