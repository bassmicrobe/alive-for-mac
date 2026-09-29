// Port of the logic of nebula/NebulaForm.cs: which channel shows what, the data, the selection.
import Foundation
import Observation
import AliveCore

@MainActor
@Observable
final class StatModel {
    @ObservationIgnored unowned let app: AppModel

    /// The animated cloud. A plain class: the canvas advances and reads it every frame; this model
    /// only pokes it and bumps `frame` to ask for a redraw.
    @ObservationIgnored let scene: CloudScene
    @ObservationIgnored let metrics: Metrics
    @ObservationIgnored private var dataRevision = -1
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// What each channel shows and the look of the dots (`nebula.cfg`).
    private(set) var config: NebulaConfig
    /// Bumped whenever the canvas has to draw again although nothing animates.
    private(set) var frame = 0
    private(set) var legend = StatLegend.off
    /// The set the inspector shows: the selected dot.
    private(set) var selectedSet: SetEntry?
    private(set) var visibleCount = 0
    /// The name under the pointer, for accessibility and the status line.
    private(set) var hoveredName = ""

    init(app: AppModel) {
        self.app = app
        let metrics = Metrics()
        self.metrics = metrics
        scene = CloudScene(metrics: metrics)
        config = NebulaConfig.load(dir: app.dataDir)
        applyConfig(animate: false)
    }

    /// The sets the cloud shows: one dot per project, and not the ones that failed to parse or
    /// Live's own backups.
    static func visibleSets(from projects: [SetEntry]) -> [SetEntry] {
        projects.filter { $0.error.isEmpty && !$0.isBackup }
    }

    // MARK: data

    /// Takes the catalog's projects in when they changed. Cheap to call often.
    func syncCatalog(force: Bool = false) {
        guard force || dataRevision != app.catalog.revision else { return }
        dataRevision = app.catalog.revision
        let visible = Self.visibleSets(from: app.catalog.projects)
        scene.setData(visible)
        visibleCount = visible.count
        refreshSelection()
        followMainSelection()
        refreshLegend()
        redraw()
    }

    /// The main window's selection is the cloud's selection ("InitialPath" upstream): when the
    /// window opens, or the selection moves in the list, the dot rings itself.
    func followMainSelection() {
        guard let path = app.selectedSetPath, path != scene.selectedSet?.path else { return }
        if scene.select(path: path) { refreshSelection(); redraw() }
    }

    private func refreshSelection() {
        selectedSet = scene.selectedSet
    }

    func refreshLegend() { legend = StatLegend.make(scene: scene) }

    /// Asks the canvas to draw once more.
    func redraw() { frame &+= 1 }

    var isAnimating: Bool { scene.isAnimating }

    // MARK: channels

    /// Pushes `config` into the scene. `animate`: the dots fly to their new places.
    private func applyConfig(animate: Bool) {
        for i in 0..<6 {
            scene.setChannel(i, metric: metrics.byId(config.ids[i]), isOn: config.isOn[i])
        }
        scene.isSpinning = config.spin
        scene.setGradient(Palette.gradient(id: config.gradientId))
        scene.setFade(min: config.minFade, max: config.maxFade)
        scene.setRadius(min: config.minSize, max: config.maxSize)
        scene.rebuild(animate: animate)
    }

    func metricId(_ channel: Int) -> String { config.ids[channel] }

    func setMetric(_ channel: Int, id: String) {
        guard config.ids.indices.contains(channel), config.ids[channel] != id else { return }
        config.ids[channel] = id
        channelsChanged()
    }

    func setChannel(_ channel: Int, isOn: Bool) {
        guard config.isOn.indices.contains(channel), config.isOn[channel] != isOn else { return }
        config.isOn[channel] = isOn
        channelsChanged()
    }

    private func channelsChanged() {
        applyConfig(animate: true)
        refreshLegend()
        redraw()
        saveSoon()
    }

    /// The palette only colours continuous values — on Key/Scale/Collection it decides nothing
    /// (those have their own per-class colouring), and offering the choice then would only confuse.
    var showsPalette: Bool { config.isOn[5] && metrics.byId(config.ids[5]).color == .ramp }

    func setGradient(id: String) {
        guard config.gradientId != id else { return }
        config.gradientId = id
        scene.setGradient(Palette.gradient(id: id))
        refreshLegend()
        redraw()
        saveSoon()
    }

    func setMinFade(_ v: Double) { config.minFade = v; fadeChanged() }
    func setMaxFade(_ v: Double) { config.maxFade = v; fadeChanged() }

    private func fadeChanged() {
        scene.setFade(min: config.minFade, max: config.maxFade)
        redraw()
        saveSoon()
    }

    func setMinSize(_ v: Double) { config.minSize = v; sizeChanged() }
    func setMaxSize(_ v: Double) { config.maxSize = v; sizeChanged() }

    private func sizeChanged() {
        scene.setRadius(min: config.minSize, max: config.maxSize)
        redraw()
        saveSoon()
    }

    // MARK: camera

    func setSpin(_ on: Bool) {
        guard config.spin != on else { return }
        config.spin = on
        scene.isSpinning = on
        redraw()
        saveSoon()
    }

    func toggleSpin() { setSpin(!config.spin) }

    /// An orthographic preset means exactly this view, with no rotation on top: the spin goes
    /// off, or a frame that has just squared up to an axis goes askew again a second later.
    func setPreset(_ preset: CameraPreset) {
        setSpin(false)
        scene.stopMotion()
        scene.camera.setPreset(preset)
        redraw()
    }

    func resetView() { setPreset(.front) }

    // MARK: pointer

    func dragBegan() { scene.isDragging = true }

    func rotate(dx: Double, dy: Double) {
        scene.camera.rotate(dx: dx, dy: dy)
        redraw()
    }

    func pan(dx: Double, dy: Double) {
        scene.camera.pan(dx: dx, dy: dy)
        redraw()
    }

    /// A released drag keeps turning for a moment when it was released moving.
    func dragEnded(yawPerSecond: Double = 0, pitchPerSecond: Double = 0) {
        scene.isDragging = false
        if abs(yawPerSecond) > 0.1 || abs(pitchPerSecond) > 0.1 {
            scene.fling(yawPerSecond: yawPerSecond, pitchPerSecond: pitchPerSecond)
        }
        redraw()
    }

    func zoom(steps: Double) {
        scene.camera.zoomBy(steps: steps)
        redraw()
    }

    /// The dot under the pointer (nil clears). True when the hover changed.
    @discardableResult
    func hover(x: Double?, y: Double?) -> Bool {
        let hit = (x != nil && y != nil) ? scene.pick(x: x ?? 0, y: y ?? 0) : -1
        guard hit != scene.hovered else { return false }
        scene.setHover(hit)
        hoveredName = scene.hoveredSet?.name ?? ""
        redraw()
        return true
    }

    var hasHover: Bool { scene.hovered >= 0 }

    /// A click on a dot selects it; on empty space it clears the selection.
    func click(x: Double, y: Double) {
        scene.select(index: scene.pick(x: x, y: y))
        refreshSelection()
        redraw()
    }

    func deselect() {
        scene.select(index: -1)
        refreshSelection()
        redraw()
    }

    // MARK: actions on the selected set

    func openSelectedInLive() {
        guard let s = selectedSet else { return }
        app.openInLive(path: s.path)
    }

    func revealSelected() {
        guard let s = selectedSet else { return }
        app.revealInFinder(path: FileManager.default.fileExists(atPath: s.path) ? s.path : s.projectDir)
    }

    /// "Show in list": the Sets tab with this set selected. The caller brings the main window
    /// forward. False when nothing is selected.
    @discardableResult
    func showSelectedInList() -> Bool {
        guard let s = selectedSet else { return false }
        app.searchText = ""
        app.tab = .sets
        app.sets.select(path: s.path)
        return true
    }

    // MARK: persistence

    /// Writes `nebula.cfg` a moment after the last change, so dragging a slider is one write.
    private func saveSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try config.save(dir: app.dataDir)
        } catch {
            Diag.fail("save nebula.cfg", error)
        }
    }
}
