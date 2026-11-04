// Mac-only: the audition volume (upstream: DetailPanel.PreviewVolume, the slider drawn right under a
// sample's wave, a6c8dc1). It is remembered as `previewvolume` in settings.cfg and reaches only the
// sample this tab plays: `app.audio` is shared with the render player, whose level is
// `app.audio.volume` and is never touched from here.
import Foundation

extension SamplesModel {
    /// How long the slider rests before the level is written to settings.cfg: a drag is one write.
    private static let volumeSaveDelay: Duration = .milliseconds(300)

    static func clampedVolume(_ v: Double) -> Double {
        v.isFinite ? min(1, max(0, v)) : 0.8
    }

    /// The slider moved. The sample that plays follows at once; the file follows a moment later.
    func setPreviewVolume(_ value: Double) {
        let v = Self.clampedVolume(value)
        guard v != previewVolume else { return }
        previewVolume = v
        applyPreviewVolume()
        volumeSaveTask?.cancel()
        volumeSaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.volumeSaveDelay)
            guard !Task.isCancelled else { return }
            self?.flushPreviewVolume()
        }
    }

    /// Writes the level to settings.cfg now (a no-op when it is already there).
    func flushPreviewVolume() {
        volumeSaveTask?.cancel()
        volumeSaveTask = nil
        let v = previewVolume
        app.mutateSettings { $0.previewVolume = v }
    }

    /// Puts the level on the sample this tab started, if it is still the one playing. It goes to the
    /// underlying player and not to `audio.volume`: that is the render player's level, and the next
    /// render builds its player from it.
    func applyPreviewVolume() {
        guard let path = startedPath, app.audio.url?.path == path else { return }
        app.audio.player?.volume = Float(previewVolume)
    }
}
