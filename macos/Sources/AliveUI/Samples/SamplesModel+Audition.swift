// Mac-only: hearing a sample (upstream: PlaySample / StopSample / ToggleSample / AuditionSelection in
// src/SamplesTab.cs). One sound at a time: it goes through the app-wide player `app.audio`, which
// the render player shares. Nothing here starts on its own: only a click, an arrow key, Space or the
// panel's wave.
import Foundation
import AliveCore

extension SamplesModel {
    /// The most recent start within which a second click of a double click does not restart the sound.
    private static let doubleClickWindow: TimeInterval = 0.4

    func isPlaying(_ path: String) -> Bool {
        app.audio.isPlaying && app.audio.url?.path == path
    }

    /// The path of the sample the selection is on, when it is one.
    var selectedFile: Int? {
        if case .file(let f)? = selectedKind { return f }
        return nil
    }

    func play(file f: Int) {
        guard f < index.files.count, index.files[f].canPreview else {
            stop()
            return
        }
        let path = index.path(of: f)
        guard FileManager.default.fileExists(atPath: path) else {
            stop()
            app.toast(CommonStrings.pathMissing.f(path), kind: .error)
            return
        }
        // A failure is reported by AppModel's `audio.onError`.
        startedPath = app.audio.play(url: URL(fileURLWithPath: path)) ? path : nil
        auditioned = path
        lastStart = Date()
    }

    /// Stops the sample this tab started — never a render the player is playing.
    func stop() {
        if let path = startedPath, app.audio.url?.path == path { app.audio.stop() }
        startedPath = nil
    }

    /// Space and the row menu: the playing one stops, any other starts. A file only Live plays
    /// silences whatever was playing here.
    func toggle(file f: Int) {
        let path = index.path(of: f)
        if isPlaying(path) || !index.files[f].canPreview { stop() } else { play(file: f) }
    }

    func togglePlaySelected() {
        if let f = selectedFile { toggle(file: f) } else { stop() }
    }

    /// A click on a row. A sample plays the moment it is selected, the way Live's browser previews;
    /// a folder stops it. A click on the row that is already selected plays its sample again — but
    /// the second click of a double click must not restart what the first has just started.
    func click(_ row: SampleRow) {
        let wasSelected = selection == row.id
        select(row.id)
        guard case .file(let f) = row.kind else {
            stop()
            auditioned = nil
            return
        }
        if wasSelected, isPlaying(row.id), Date().timeIntervalSince(lastStart) < Self.doubleClickWindow { return }
        play(file: f)
    }

    /// Up and down arrows: select the neighbour row (and audition it, like a click).
    func moveSelection(by delta: Int) {
        let rows = listing.rows
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selection }
        let next = current.map { min(rows.count - 1, max(0, $0 + delta)) } ?? (delta > 0 ? 0 : rows.count - 1)
        click(rows[next])
        requestScroll(to: rows[next].id)
    }

    /// Enter or a double click. A folder in the tree opens or closes; in a flat list it is shown in
    /// the tree. A sample plays — unless it already does.
    func activate(_ row: SampleRow) {
        switch row.kind {
        case .folder:
            if isFlat { showInTree(row.id) } else { toggleFolder(row.id) }
        case .file(let f):
            if !isPlaying(row.id) { play(file: f) }
        }
    }

    /// A click on the wave in the panel: play from there.
    func seek(toFraction t: Double) {
        guard let f = selectedFile, index.files[f].canPreview else { return }
        let path = index.path(of: f)
        if !isPlaying(path) { play(file: f) }
        guard let d = info?.durationMs, d > 0 else {
            app.audio.seek(to: t * app.audio.duration)
            return
        }
        app.audio.seek(to: t * Double(d) / 1000)
    }

    /// The tab is left: the preview belongs to it, and coming back to the same sample plays it again.
    func leave() {
        stop()
        auditioned = nil
    }

    /// The file a drag out of the list carries.
    func dragURL(for row: SampleRow) -> URL? {
        guard case .file = row.kind, FileManager.default.fileExists(atPath: row.id) else { return nil }
        return URL(fileURLWithPath: row.id)
    }
}
