// Port of the logic half of src/PlayerDialog.cs: which render of a set to play, waveform, transport,
// the pinned "main" render. Sound goes through the app-wide `app.audio`.
import AliveCore
import Foundation
import Observation

@MainActor
@Observable
final class PlayerModel {
    /// Columns of the waveform envelope; the view scales it to its width.
    nonisolated static let waveformBuckets = 1200

    @ObservationIgnored unowned let app: AppModel

    /// The set whose renders are listed (path of the .als), nil until something was loaded.
    private(set) var setPath: String?
    private(set) var setName = ""
    private(set) var files: [RenderFile] = []
    private(set) var currentIndex: Int?
    /// nil while the envelope of the current file is being read.
    private(set) var waveform: Waveform?
    private(set) var isSearching = false
    /// Playback was started for the current set at least once: only then does Home show the strip.
    private(set) var hasPlayed = false
    /// Where to start when play is pressed (a click on the waveform before the file was opened).
    private(set) var pendingSeek: Double?

    /// Off in tests: registering with the system's media controls is a global side effect.
    @ObservationIgnored var systemMediaEnabled = true
    @ObservationIgnored let pins: PreviewPins
    @ObservationIgnored private var mediaKeys: MediaKeys?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var waveformTask: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        pins = PreviewPins(dir: app.dataDir)
    }

    /// The app-wide player (`app.audio`), shared with sample audition.
    var audio: AudioPlayback { app.audio }

    // MARK: - State

    var currentFile: RenderFile? {
        guard let i = currentIndex, files.indices.contains(i) else { return nil }
        return files[i]
    }

    var hasFiles: Bool { !files.isEmpty }

    /// The shared player has the current file open (it may be paused).
    var isCurrentOpen: Bool {
        guard let file = currentFile, let url = audio.url else { return false }
        return url.path == URL(fileURLWithPath: file.path).path
    }

    var isPlaying: Bool { isCurrentOpen && audio.isPlaying }

    func isPlaying(setPath path: String) -> Bool {
        guard let setPath else { return false }
        return isPlaying && setPath.caseInsensitiveCompare(path) == .orderedSame
    }

    var duration: TimeInterval { isCurrentOpen ? audio.duration : (waveform?.duration ?? 0) }

    /// 0...1
    var progress: Double {
        guard isCurrentOpen else { return pendingSeek ?? 0 }
        return audio.duration > 0 ? min(1, max(0, audio.currentTime / audio.duration)) : 0
    }

    var position: TimeInterval { progress * duration }

    /// What the window says when there is nothing to hear.
    var note: String? {
        if isSearching { return HomeStrings.playerLoading.s }
        if setPath != nil, files.isEmpty { return HomeStrings.noRenders.s }
        return nil
    }

    /// Home shows a compact strip while a set of the player has been played.
    var isStripVisible: Bool { hasPlayed && currentFile != nil }

    var volume: Float {
        get { audio.volume }
        set { audio.volume = min(1, max(0, newValue)) }
    }

    // MARK: - Loading

    /// Cross-feature entry point (tile play button, Space, context menu): plays the set's best
    /// render; on the set that is already loaded it toggles pause instead.
    func playRender(forSetAt path: String) {
        Task { await playRender(forSetAt: path, autoStart: true) }
    }

    func playRender(forSetAt path: String, autoStart: Bool) async {
        if isLoaded(path), currentFile != nil {
            if autoStart { togglePlayPause() }
            return
        }
        await load(setAt: path, autoStart: autoStart)
    }

    private func isLoaded(_ path: String) -> Bool {
        setPath?.caseInsensitiveCompare(path) == .orderedSame
    }

    /// Lists the set's renders (pinned first, then newest) and selects the first. With
    /// `autoStart` false nothing sounds until play is pressed.
    func load(setAt path: String, autoStart: Bool) async {
        generation += 1
        let gen = generation
        stopIfOurs()
        let entry = app.catalog.sets.first { $0.path.caseInsensitiveCompare(path) == .orderedSame } ?? Self.bareEntry(path)
        setPath = entry.path
        setName = entry.name
        files = []
        currentIndex = nil
        waveform = nil
        pendingSeek = nil
        hasPlayed = false
        isSearching = true

        let pins = pins
        let found = await Task.detached(priority: .userInitiated) { RenderScan.find(entry, pins: pins) }.value
        guard gen == generation else { return }
        isSearching = false
        files = found
        guard !found.isEmpty else {
            waveformTask?.cancel()
            return
        }
        select(0, autoStart: autoStart)
    }

    /// A set the catalog does not know (opened from outside): the path is all RenderScan needs.
    private static func bareEntry(_ path: String) -> SetEntry {
        var e = SetEntry()
        e.path = path
        e.name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return e
    }

    /// Makes `index` the current render, reads its envelope and (optionally) starts it.
    func select(_ index: Int, autoStart: Bool) {
        guard files.indices.contains(index) else { return }
        if index != currentIndex { stopIfOurs() }
        currentIndex = index
        pendingSeek = nil
        requestWaveform(for: files[index])
        if autoStart { startPlayback() } else { refreshNowPlaying() }
    }

    private func requestWaveform(for file: RenderFile) {
        waveformTask?.cancel()
        waveform = nil
        let path = file.path
        waveformTask = Task { [weak self] in
            let peaks = await Task.detached(priority: .userInitiated) {
                WaveformReader.read(path: path, buckets: PlayerModel.waveformBuckets)
            }.value
            guard !Task.isCancelled, let self, self.currentFile?.path == path else { return }
            self.waveform = peaks
        }
    }

    // MARK: - Transport

    private func startPlayback() {
        guard let file = currentFile else { return }
        guard audio.play(url: URL(fileURLWithPath: file.path)) else { return }
        hasPlayed = true
        if let f = pendingSeek, audio.duration > 0 { audio.seek(to: f * audio.duration) }
        pendingSeek = nil
        activateMediaKeys()
        refreshNowPlaying()
    }

    func togglePlayPause() {
        if isCurrentOpen {
            audio.togglePlayPause()
            refreshNowPlaying()
        } else if currentFile != nil {
            startPlayback()
        } else if let selected = app.selectedSetPath, app.catalog.sets.contains(where: { $0.path == selected && $0.hasRenders }) {
            playRender(forSetAt: selected)
        }
    }

    /// 0...1 of the current file. Before the file is opened the position is kept for play.
    func seek(toFraction fraction: Double) {
        let f = min(1, max(0, fraction))
        if isCurrentOpen {
            audio.seek(to: f * audio.duration)
        } else {
            pendingSeek = f
        }
        refreshNowPlaying()
    }

    /// The previous / next render of the set. false when there is none in that direction.
    @discardableResult
    func stepFile(_ delta: Int, autoStart: Bool = true) -> Bool {
        guard let i = currentIndex, files.indices.contains(i + delta) else { return false }
        select(i + delta, autoStart: autoStart)
        return true
    }

    /// The neighbouring set (with renders) of the Home list; wraps around. The set we stand on
    /// does not count as a candidate, so a list of one never loops onto itself.
    @discardableResult
    func stepSet(_ delta: Int, autoStart: Bool = true) async -> Bool {
        guard let path = Self.neighbour(of: setPath, in: app.home.rows, delta: delta) else { return false }
        await load(setAt: path, autoStart: autoStart)
        return true
    }

    /// Pure choice of the neighbouring set for `stepSet`.
    static func neighbour(of current: String?, in list: [SetEntry], delta: Int) -> String? {
        guard !list.isEmpty, delta != 0 else { return nil }
        let start = list.firstIndex { $0.path.caseInsensitiveCompare(current ?? "") == .orderedSame } ?? (delta > 0 ? -1 : list.count)
        for step in 1...list.count {
            let candidate = list[((start + delta * step) % list.count + list.count) % list.count]
            if candidate.path.caseInsensitiveCompare(current ?? "") == .orderedSame { continue }
            if candidate.hasRenders { return candidate.path }
        }
        return nil
    }

    /// Stops the sound and forgets the loaded set (the strip's close button).
    func unload() {
        generation += 1
        waveformTask?.cancel()
        stopIfOurs()
        setPath = nil
        setName = ""
        files = []
        currentIndex = nil
        waveform = nil
        hasPlayed = false
        pendingSeek = nil
        isSearching = false
        deactivateMediaKeys()
    }

    /// The window (or a sample audition) may own the shared player; only stop what is ours.
    private func stopIfOurs() {
        guard isCurrentOpen else { return }
        audio.stop()
    }

    // MARK: - Pinning the main render

    /// Marks the render as the set's preview (a second call on the pinned one clears it).
    func togglePin(_ file: RenderFile) async {
        guard let path = setPath else { return }
        let root = RenderScan.projectRoot(entryForCurrentSet(path))
        guard !root.isEmpty else { return }
        if file.pinned { pins.clear(root) } else { pins.set(root, file: file.path) }
        let playing = currentFile?.path
        let entry = entryForCurrentSet(path)
        let pins = pins
        let found = await Task.detached(priority: .userInitiated) { RenderScan.find(entry, pins: pins) }.value
        guard setPath == path else { return }
        files = found
        currentIndex = playing.flatMap { p in found.firstIndex { $0.path.caseInsensitiveCompare(p) == .orderedSame } }
    }

    private func entryForCurrentSet(_ path: String) -> SetEntry {
        app.catalog.sets.first { $0.path.caseInsensitiveCompare(path) == .orderedSame } ?? Self.bareEntry(path)
    }

    // MARK: - Media keys / Now Playing

    /// What a media key does. The next/previous keys go to the neighbouring render, then to the
    /// neighbouring set (upstream `Step`).
    func apply(_ command: MediaKeys.Command) {
        switch command {
        case .playPause: togglePlayPause()
        case .play: if !isPlaying { togglePlayPause() }
        case .pause: if isPlaying { togglePlayPause() }
        case .stop: audio.pause()
        case .next: step(+1)
        case .previous: step(-1)
        }
        refreshNowPlaying()
    }

    private func step(_ delta: Int) {
        if stepFile(delta) { return }
        Task { _ = await stepSet(delta) }
    }

    private func activateMediaKeys() {
        guard systemMediaEnabled else { return }
        if mediaKeys == nil { mediaKeys = MediaKeys { [weak self] in self?.apply($0) } }
        mediaKeys?.activate()
    }

    private func deactivateMediaKeys() {
        mediaKeys?.deactivate()
    }

    private func refreshNowPlaying() {
        guard let file = currentFile, isCurrentOpen else { return }
        mediaKeys?.update(MediaKeys.Info(title: file.name, artist: setName, elapsed: audio.currentTime,
                                         duration: audio.duration, isPlaying: audio.isPlaying))
    }
}
