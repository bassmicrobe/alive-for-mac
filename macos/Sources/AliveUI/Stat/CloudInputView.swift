// Mac-only: mouse, trackpad and keys for the cloud. SwiftUI has no scroll-wheel gesture on macOS 14
// and its DragGesture cannot see the right button, so one NSView sits over the canvas
// (upstream: the mouse handlers of CloudView in nebula/Cloud.cs).
import SwiftUI
import AppKit

struct CloudInputView: NSViewRepresentable {
    let model: StatModel
    /// Return / double click / space etc. that the window itself acts on.
    var onKey: (CloudKey) -> Void
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> CloudInputNSView {
        let view = CloudInputNSView()
        view.model = model
        view.onKey = onKey
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ view: CloudInputNSView, context: Context) {
        view.model = model
        view.onKey = onKey
        view.onDoubleClick = onDoubleClick
    }
}

enum CloudKey {
    case toggleSpin, reset, openInLive, deselect
}

final class CloudInputNSView: NSView {
    var model: StatModel?
    var onKey: (CloudKey) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}

    private enum Drag { case none, rotate, pan }
    private var drag = Drag.none
    private var moved = false
    private var downPoint = CGPoint.zero
    /// Smoothed pointer speed (points per second) for the inertia of a released rotation.
    private var velocity = CGVector.zero
    private var lastDragTime: TimeInterval = 0
    private var tracking: NSTrackingArea?

    /// A click that moved less than this is a click, not a drag.
    private static let clickSlop = 3.0
    /// A rotation released later than this after its last movement had stopped: no inertia.
    private static let flingWindow = 0.06

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private func local(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    // MARK: pointer

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // Trackpad users have no right button: ⌥ or ⇧ with the drag pans as well.
        begin(event, pan: !event.modifierFlags.isDisjoint(with: [.option, .shift]))
    }

    override func rightMouseDown(with event: NSEvent) { begin(event, pan: true) }
    override func otherMouseDown(with event: NSEvent) { begin(event, pan: true) }

    private func begin(_ event: NSEvent, pan: Bool) {
        drag = pan ? .pan : .rotate
        moved = false
        downPoint = local(event)
        velocity = .zero
        lastDragTime = event.timestamp
        if drag == .rotate { model?.dragBegan() }
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) { dragged(event) }
    override func rightMouseDragged(with event: NSEvent) { dragged(event) }
    override func otherMouseDragged(with event: NSEvent) { dragged(event) }

    private func dragged(_ event: NSEvent) {
        guard drag != .none, let model else { return }
        let p = local(event)
        if hypot(p.x - downPoint.x, p.y - downPoint.y) > Self.clickSlop { moved = true }
        let dx = Double(event.deltaX), dy = Double(event.deltaY)
        if drag == .rotate {
            model.rotate(dx: dx, dy: dy)
            let dt = max(0.001, event.timestamp - lastDragTime)
            velocity = CGVector(dx: velocity.dx * 0.5 + (dx / dt) * 0.5, dy: velocity.dy * 0.5 + (dy / dt) * 0.5)
        } else {
            model.pan(dx: dx, dy: dy)
        }
        lastDragTime = event.timestamp
    }

    override func mouseUp(with event: NSEvent) { finish(event, left: true) }
    override func rightMouseUp(with event: NSEvent) { finish(event, left: false) }
    override func otherMouseUp(with event: NSEvent) { finish(event, left: false) }

    private func finish(_ event: NSEvent, left: Bool) {
        guard let model else { return }
        let wasRotating = drag == .rotate
        drag = .none
        if wasRotating {
            let fresh = event.timestamp - lastDragTime < Self.flingWindow
            let k = CloudCamera.dragRadiansPerPoint
            model.dragEnded(yawPerSecond: fresh && moved ? -Double(velocity.dx) * k : 0,
                            pitchPerSecond: fresh && moved ? -Double(velocity.dy) * k : 0)
        }
        let p = local(event)
        if left, !moved {
            if event.clickCount >= 2 {
                onDoubleClick()
            } else {
                model.click(x: p.x, y: p.y)
            }
        }
        model.hover(x: p.x, y: p.y)
        cursor(for: model.hasHover)
    }

    override func mouseMoved(with event: NSEvent) {
        guard drag == .none, let model else { return }
        let p = local(event)
        model.hover(x: p.x, y: p.y)
        cursor(for: model.hasHover)
    }

    override func mouseExited(with event: NSEvent) {
        model?.hover(x: nil, y: nil)
        NSCursor.arrow.set()
    }

    private func cursor(for hit: Bool) {
        (hit ? NSCursor.pointingHand : NSCursor.crosshair).set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: zoom

    override func scrollWheel(with event: NSEvent) {
        // A wheel notch is one step; a trackpad reports many small precise deltas.
        let steps = event.hasPreciseScrollingDeltas ? Double(event.scrollingDeltaY) / 14 : Double(event.scrollingDeltaY)
        guard steps != 0 else { return }
        model?.zoom(steps: steps)
    }

    override func magnify(with event: NSEvent) {
        // Pinch: the magnification is a fraction of the current scale.
        model?.zoom(steps: log(1 + Double(event.magnification)) / log(CloudCamera.wheelStep))
    }

    // MARK: keys

    /// Moves the selection to the next (`+1`) or previous (`-1`) project. The main window's
    /// selection is the cloud's selection (`StatModel.followMainSelection`), so it goes through it.
    @discardableResult
    private func selectAdjacent(_ step: Int) -> Bool {
        guard let model else { return false }
        let sets = model.scene.sets
        guard !sets.isEmpty else { return false }
        let current = model.scene.selected
        let next = current < 0 ? (step > 0 ? 0 : sets.count - 1) : (current + step + sets.count) % sets.count
        model.app.selectedSetPath = sets[next].path
        model.followMainSelection()
        NSAccessibility.post(element: self, notification: .valueChanged)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.isDisjoint(with: [.command, .control]) else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 123, 126: selectAdjacent(-1)      // left, up
        case 124, 125: selectAdjacent(+1)      // right, down
        case 49: onKey(.toggleSpin)            // space
        case 15: onKey(.reset)                 // R
        case 36, 76: onKey(.openInLive)        // return, enter
        case 53: onKey(.deselect)              // escape
        default: super.keyDown(with: event)
        }
    }

    // MARK: accessibility
    // The dots are drawn in one Canvas, so VoiceOver gets this view instead: a labelled group whose
    // value is the selected project, with the actions the keys and the double click stand for.

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityLabel() -> String? {
        StatStrings.cloudLabel.f(model?.visibleCount ?? 0)
    }

    override func accessibilityValue() -> Any? {
        model?.selectedSet?.name ?? StatStrings.noProjectSelected.s
    }

    override func accessibilityHelp() -> String? { StatStrings.cloudHelp.s }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions = [
            NSAccessibilityCustomAction(name: StatStrings.nextProject.s) { [weak self] in self?.selectAdjacent(+1) ?? false },
            NSAccessibilityCustomAction(name: StatStrings.previousProject.s) { [weak self] in self?.selectAdjacent(-1) ?? false },
        ]
        if model?.selectedSet != nil {
            actions.insert(NSAccessibilityCustomAction(name: CommonStrings.openInLive.s) { [weak self] in
                self?.onKey(.openInLive); return true
            }, at: 0)
            actions.insert(NSAccessibilityCustomAction(name: CommonStrings.showInFinder.s) { [weak self] in
                self?.onDoubleClick(); return true
            }, at: 1)
        }
        return actions
    }
}
