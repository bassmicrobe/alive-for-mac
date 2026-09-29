// Port of the data part of nebula/Cloud.cs (CloudView: Rebuild, Coord, ColorOf, AlphaOf, Pick).
import Foundation
import CoreGraphics
import AliveCore

/// One dot of the cloud.
struct CloudNode {
    /// A row in `CloudScene.sets`.
    var index = 0
    /// Where the dot is heading, and where it is now — the cloud rebuilds itself smoothly.
    var tx = 0.0, ty = 0.0, tz = 0.0
    var x = 0.0, y = 0.0, z = 0.0
    /// 0…1 along the Size channel.
    var size = 0.0
    var alpha = 0.0
    var rgb = 0
    /// The shimmer phase.
    var phase = 0.0
    /// The screen position after projection (set by `project`).
    var sx = 0.0, sy = 0.0, sr = 0.0, depth = 1.0
}

/// The cloud itself: six values of a set turn into three coordinates, plus the size, density and
/// colour of a dot. A plain class, deliberately not observable: the canvas advances and reads it
/// every frame, and the windows' models only poke it and bump a token to request a redraw.
final class CloudScene {
    private(set) var sets: [SetEntry] = []
    private(set) var nodes: [CloudNode] = []

    var x: Axis, y: Axis, z: Axis, size: Axis, alpha: Axis, color: Axis
    var gradient = Palette.gradients[0]
    var camera = CloudCamera()
    var isSpinning = false

    private(set) var minAlpha = 0.08
    private(set) var maxAlpha = 1.0
    private(set) var minRadius = 1.0
    private(set) var maxRadius = 16.0

    private(set) var hovered = -1
    private(set) var selected = -1

    /// While the pointer holds the cloud the spin waits (and so does the inertia).
    var isDragging = false {
        didSet { if isDragging { yawVelocity = 0; pitchVelocity = 0 } }
    }

    // Edge hysteresis for the axis labels (see CloudAxisLabels): -1 = none chosen yet.
    var lastEdge = [-1, -1, -1]

    private var settle = 0.0
    private var yawVelocity = 0.0
    private var pitchVelocity = 0.0
    private var lastTime: Date?

    /// What a channel that is off looks like — neutral, not "no data" (see `rebuild`).
    static let sizeWhenOff = 0.40
    static let sizeWhenMissing = 0.25
    static let alphaWhenOff = 0.82
    static let alphaWhenMissing = 0.30
    private static let offRgb = RGB8(0xCA, 0xCA, 0xCB).packed
    /// Radians per second of the idle spin (upstream: 0.0016 per 16 ms frame).
    static let spinSpeed = 0.096
    /// Below this angular speed (rad/s) the drag inertia stops.
    private static let inertiaFloor = 0.02

    init(metrics: Metrics) {
        let m = metrics.all
        x = Axis(metric: m[0]); y = Axis(metric: m[1]); z = Axis(metric: m[2])
        size = Axis(metric: m[3]); alpha = Axis(metric: m[4]); color = Axis(metric: m[5])
    }

    // MARK: data

    var hoveredSet: SetEntry? { at(hovered) }
    var selectedSet: SetEntry? { at(selected) }

    private func at(_ i: Int) -> SetEntry? { sets.indices.contains(i) ? sets[i] : nil }

    /// Replaces the sets. The selection follows its path into the new list; the hover is dropped.
    func setData(_ newSets: [SetEntry]) {
        let keep = selectedSet?.path
        sets = newSets
        rebuild(animate: false)
        selected = keep.flatMap { p in sets.firstIndex { $0.path == p } } ?? -1
        hovered = -1
    }

    /// Recomputing all six channels. `animate`: the dots do not jump to their new places but fly
    /// to them — otherwise changing the value on an axis looks like the picture being swapped,
    /// and the connection between "before" and "after" is lost.
    func rebuild(animate: Bool) {
        // A channel that is off does not compute its scale at all — it does not need one, and on
        // categories like Key an extra pass over every set costs noticeable milliseconds.
        for i in 0..<6 {
            if axis(i).isOn { mutate(i) { $0.fit(sets) } } else { mutate(i) { $0.clear() } }
        }
        let old = nodes
        var fresh = [CloudNode](repeating: CloudNode(), count: sets.count)
        for i in sets.indices {
            let s = sets[i]
            var n = CloudNode()
            n.index = i
            let jitter = Metrics.hash01(s.path)
            n.tx = Self.coord(x, s, jitter, 0)
            n.ty = Self.coord(y, s, jitter, 1)
            n.tz = Self.coord(z, s, jitter, 2)
            n.size = sizeOf(s)
            n.alpha = alphaOf(s)
            n.rgb = colorOf(s).packed
            n.phase = jitter * .pi * 2
            if animate, i < old.count, old[i].index == i {
                // A dot that already lived in the cloud starts from its previous place.
                n.x = old[i].x; n.y = old[i].y; n.z = old[i].z
            } else if animate {
                n.x = 0; n.y = 0; n.z = 0
            } else {
                n.x = n.tx; n.y = n.ty; n.z = n.tz
            }
            fresh[i] = n
        }
        nodes = fresh
        if animate { settle = 1 }
    }

    /// A value → a coordinate in the [-1, 1] cube. With no data, as on a channel that is off, it
    /// is the centre with a scatter, so that such sets do not stick together into one dot and it
    /// is visible how many of them there are.
    static func coord(_ a: Axis, _ s: SetEntry, _ jitter: Double, _ seed: Int) -> Double {
        let t = a.isOn ? a.range.norm(a.metric.value(s)) : .nan
        if t.isNaN {
            return ((jitter * 7.13 + Double(seed) * 0.37).truncatingRemainder(dividingBy: 1) - 0.5) * 0.12
        }
        // A small scatter: with whole-number values (24 tracks, 120 BPM) the dots otherwise lie
        // exactly on top of each other and the density does not read.
        let j = ((jitter * 13.7 + Double(seed) * 2.31).truncatingRemainder(dividingBy: 1) - 0.5) * 0.022
        return (t - 0.5) * 2 + j
    }

    /// A size or fade channel that is off gives every dot one and the same look — not "no data"
    /// (a dull grey somewhere in the middle of the scale) but exactly neutral, because this is not
    /// a gap in the data but a decision to remove the channel altogether.
    private func sizeOf(_ s: SetEntry) -> Double {
        guard size.isOn else { return Self.sizeWhenOff }
        let v = size.range.norm(size.metric.value(s))
        return v.isNaN ? Self.sizeWhenMissing : v
    }

    private func alphaOf(_ s: SetEntry) -> Double {
        guard alpha.isOn else { return Self.alphaWhenOff }
        let v = alpha.range.norm(alpha.metric.value(s))
        return v.isNaN ? Self.alphaWhenMissing : minAlpha + (maxAlpha - minAlpha) * v
    }

    /// Colour switched off is not "no data" (dull grey) but the same light neutral tone that
    /// highlights the rest of the interface.
    func colorOf(_ s: SetEntry) -> RGB8 {
        guard color.isOn else { return RGB8(hex: Self.offRgb) }
        let m = color.metric
        let v = m.value(s)
        switch m.color {
        case .key: return Palette.key(root: s.scaleRoot, scaleIndex: s.scaleIndex)
        case .classes: return v.isNaN ? Palette.unknown : Palette.classColor(Int(v))
        case .ramp: return Palette.sample(gradient, color.range.norm(v))
        }
    }

    private func axis(_ i: Int) -> Axis { [x, y, z, size, alpha, color][i] }

    private func mutate(_ i: Int, _ change: (inout Axis) -> Void) {
        switch i {
        case 0: change(&x)
        case 1: change(&y)
        case 2: change(&z)
        case 3: change(&size)
        case 4: change(&alpha)
        default: change(&color)
        }
    }

    /// Points a channel at a metric and switches it; the caller rebuilds afterwards.
    func setChannel(_ i: Int, metric: Metric, isOn: Bool) {
        mutate(i) { $0.metric = metric; $0.isOn = isOn }
    }

    func setGradient(_ g: StatGradient) {
        guard g != gradient else { return }
        gradient = g
        recolor()
    }

    /// Recolour the cloud without rebuilding the geometry: changing the palette touches neither
    /// the coordinates nor the size — only the colour — and must not trigger the fly-out
    /// animation a full rebuild does.
    func recolor() {
        for i in nodes.indices { nodes[i].rgb = colorOf(sets[nodes[i].index]).packed }
    }

    func setFade(min lo: Double, max hi: Double) {
        minAlpha = lo; maxAlpha = hi
        for i in nodes.indices { nodes[i].alpha = alphaOf(sets[nodes[i].index]) }
    }

    /// The radius in points for a dot with the smallest and with the largest value of the Size
    /// channel. Only the radius the node's 0…1 size unfolds into when drawing, so moving the
    /// slider does not rebuild.
    func setRadius(min lo: Double, max hi: Double) { minRadius = lo; maxRadius = hi }

    // MARK: selection

    func setHover(_ i: Int) { hovered = sets.indices.contains(i) ? i : -1 }

    /// Selects the set with this path (nil / unknown clears).
    @discardableResult
    func select(path: String?) -> Bool {
        let i = path.flatMap { p in sets.firstIndex { $0.path == p } } ?? -1
        selected = i
        return i >= 0
    }

    func select(index i: Int) { selected = sets.indices.contains(i) ? i : -1 }

    // MARK: motion

    /// True while something moves and the canvas needs frames: the fly-out after a rebuild, the
    /// idle spin, the inertia of a released drag.
    var isAnimating: Bool {
        settle > 0.001 || (isSpinning && !isDragging) || abs(yawVelocity) > Self.inertiaFloor
            || abs(pitchVelocity) > Self.inertiaFloor
    }

    /// A drag was released at this angular speed (rad/s): the scene keeps turning and slows down.
    func fling(yawPerSecond: Double, pitchPerSecond: Double) {
        yawVelocity = yawPerSecond
        pitchVelocity = pitchPerSecond
        lastTime = nil
    }

    /// Moves the scene up to `now`. Time-based, so a 120 Hz display does not run twice as fast
    /// as a 60 Hz one, and a long pause between frames (the timeline was paused) is one short step.
    func advance(to now: Date) {
        defer { lastTime = now }
        guard let last = lastTime else { return }
        step(dt: min(1.0 / 15.0, max(0, now.timeIntervalSince(last))))
    }

    func step(dt: Double) {
        let frames = dt * 60
        if settle > 0.001 {
            settle *= pow(0.88, frames)
            let follow = 1 - pow(0.86, frames)
            for i in nodes.indices {
                nodes[i].x += (nodes[i].tx - nodes[i].x) * follow
                nodes[i].y += (nodes[i].ty - nodes[i].y) * follow
                nodes[i].z += (nodes[i].tz - nodes[i].z) * follow
            }
            if settle <= 0.001 {
                settle = 0
                for i in nodes.indices { nodes[i].x = nodes[i].tx; nodes[i].y = nodes[i].ty; nodes[i].z = nodes[i].tz }
            }
        }
        if isSpinning && !isDragging { camera.yaw += Self.spinSpeed * dt }
        if !isDragging, abs(yawVelocity) > Self.inertiaFloor || abs(pitchVelocity) > Self.inertiaFloor {
            camera.yaw += yawVelocity * dt
            camera.setPitch(camera.pitch + pitchVelocity * dt)
            let decay = pow(0.92, frames)
            yawVelocity *= decay
            pitchVelocity *= decay
            if abs(yawVelocity) <= Self.inertiaFloor && abs(pitchVelocity) <= Self.inertiaFloor {
                yawVelocity = 0; pitchVelocity = 0
            }
        }
    }

    func stopMotion() { yawVelocity = 0; pitchVelocity = 0 }

    // MARK: projection and picking

    /// Places every dot on the screen: position, radius (with the perspective factor) and depth.
    func project(size canvas: CGSize, scale: Double = 1) {
        let p = camera.projector(size: canvas)
        let base = minRadius * scale
        let span = max(0, maxRadius - minRadius) * scale
        // Ordinary perspective (not ortho) increases k for dots closer to the camera — without
        // headroom a dot at the maximum slider setting would also swell past that very maximum
        // when in the foreground.
        let cap = max(maxRadius * 2.2, 34) * scale
        for i in nodes.indices {
            let q = p.project(nodes[i].x, nodes[i].y, nodes[i].z)
            nodes[i].sx = q.sx; nodes[i].sy = q.sy; nodes[i].depth = q.k
            nodes[i].sr = min(cap, (base + span * nodes[i].size) * q.k)
        }
    }

    /// The nearest dot under the pointer, or -1. Of overlapping ones the closer to the camera
    /// wins — aiming at the topmost is the logical thing. Uses the positions of the last
    /// `project`.
    func pick(x mx: Double, y my: Double, reach: Double = 9) -> Int {
        Self.pick(in: nodes, x: mx, y: my, reach: reach)
    }

    static func pick(in nodes: [CloudNode], x mx: Double, y my: Double, reach: Double = 9) -> Int {
        var best = -1
        var bestScore = Double.greatestFiniteMagnitude
        for (i, n) in nodes.enumerated() {
            let d = hypot(n.sx - mx, n.sy - my)
            let r = max(n.sr, reach)
            if d > r { continue }
            let score = d / r - n.depth * 0.35
            if score < bestScore { bestScore = score; best = i }
        }
        return best
    }
}
