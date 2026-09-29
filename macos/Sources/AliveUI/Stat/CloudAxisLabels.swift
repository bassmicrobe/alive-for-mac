// Port of DrawAxis / GetCandidate / Label in nebula/Cloud.cs (the axis captions of the cube).
import Foundation
import CoreGraphics

/// A caption placed on the canvas; `center` is where the middle of its text goes.
struct PlacedLabel: Equatable {
    var text: String
    var center: CGPoint
    /// The axis title (bright) as opposed to an edge value (dim).
    var isTitle: Bool
    var isDim: Bool
}

/// The axis labels. The edge to label is chosen by the picture rather than by number: of the four
/// parallel ones we take the one whose midpoint is furthest from the centre of the scene — it is
/// always outside the cloud and the label does not drown among the dots.
enum CloudAxisLabels {
    /// A new edge has to beat the current one by this much (points) before the label moves:
    /// that rules out chatter and flicker while spinning.
    static let hysteresis = 16.0
    /// Between the dots that sit right on the cube's edge and a caption.
    private static let clearance = 8.0

    /// `titles` are the three "X · Tracks" captions. `measure(text, isTitle)` sizes a text in the
    /// font the caller draws it with.
    static func layout(scene: CloudScene, size: CGSize, titles: [String],
                       measure: (String, Bool) -> CGSize) -> [PlacedLabel] {
        let proj = scene.camera.projector(size: size)
        let zone = DataZone(proj: proj, reach: reach(scene))
        var out: [PlacedLabel] = []
        let axes = [scene.x, scene.y, scene.z]
        for dim in 0..<3 {
            out += axisLabels(dim: dim, axis: axes[dim], title: titles[dim], proj: proj, scene: scene,
                              size: size, gap: zone.reach + clearance, measure: measure)
                .filter { !zone.covers(rect(of: $0, measure: measure)) }
        }
        return out
    }

    private static func rect(of l: PlacedLabel, measure: (String, Bool) -> CGSize) -> CGRect {
        let s = measure(l.text, l.isTitle)
        return CGRect(x: l.center.x - s.width / 2, y: l.center.y - s.height / 2, width: s.width, height: s.height)
    }

    /// How far a dot on the cube's edge reaches past it (its drawn radius; perspective swells it).
    static func reach(_ scene: CloudScene) -> Double {
        scene.maxRadius * (scene.camera.isOrtho ? 1 : 1.5)
    }

    /// The region the data occupies on screen: the cube's silhouette grown by the dot radius. A
    /// caption that would end up inside it (zoomed in, panned, at a canvas edge) is left out rather
    /// than drawn over the dots.
    struct DataZone {
        private let hull: [CGPoint]
        let reach: Double

        init(proj: Projector, reach: Double) {
            var pts: [CGPoint] = []
            for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] {
                let q = proj.project(x, y, z)
                pts.append(CGPoint(x: q.sx, y: q.sy))
            } } }
            hull = Self.convexHull(pts)
            self.reach = reach
        }

        func covers(_ r: CGRect) -> Bool {
            let pts = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY),
                       CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.midY),
                       CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.midX, y: r.maxY),
                       CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY)]
            return pts.contains(where: inside)
        }

        private func inside(_ p: CGPoint) -> Bool {
            guard hull.count >= 3 else { return false }
            // Counter-clockwise hull: inside means on the left of every edge, or within `reach`.
            for i in hull.indices {
                let a = hull[i], b = hull[(i + 1) % hull.count]
                let len = hypot(b.x - a.x, b.y - a.y)
                if len < 0.001 { continue }
                let side = ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)) / len
                if side < -reach { return false }
            }
            return true
        }

        private static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
            let p = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
            func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
                (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
            }
            var lower: [CGPoint] = [], upper: [CGPoint] = []
            for q in p {
                while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
                lower.append(q)
            }
            for q in p.reversed() {
                while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
                upper.append(q)
            }
            return Array(lower.dropLast() + upper.dropLast())
        }
    }

    /// The two ends of the `i`-th candidate edge of an axis. For X and Z the axes are always tied
    /// to the floor of the cube (y = -1), so the labels of the horizontal scales are always below
    /// the cube and never climb onto the ceiling. For Y one of the four vertical pillars is chosen.
    static func candidate(dim: Int, _ i: Int) -> (a: (Double, Double, Double), b: (Double, Double, Double)) {
        switch dim {
        case 0:
            let z = i == 0 ? -1.0 : 1.0
            return ((-1, -1, z), (1, -1, z))
        case 2:
            let x = i == 0 ? -1.0 : 1.0
            return ((x, -1, -1), (x, -1, 1))
        default:
            let x = (i == 1 || i == 2) ? 1.0 : -1.0
            let z = (i == 2 || i == 3) ? 1.0 : -1.0
            return ((x, -1, z), (x, 1, z))
        }
    }

    private struct Edge {
        var a = CGPoint.zero, b = CGPoint.zero, len = 0.0, score = -Double.greatestFiniteMagnitude
    }

    private static func axisLabels(dim: Int, axis a: Axis, title: String, proj: Projector, scene: CloudScene,
                                   size: CGSize, gap: Double, measure: (String, Bool) -> CGSize) -> [PlacedLabel] {
        let count = dim == 1 ? 4 : 2
        var best = Edge(), bestIdx = 0
        var last = Edge()
        let lastIdx = scene.lastEdge[dim]

        for i in 0..<count {
            let c = candidate(dim: dim, i)
            let p1 = proj.project(c.a.0, c.a.1, c.a.2)
            let p2 = proj.project(c.b.0, c.b.1, c.b.2)
            let dx = p2.sx - p1.sx, dy = p2.sy - p1.sy
            let len = hypot(dx, dy)
            if len < 1 { continue }
            let mx = (p1.sx + p2.sx) / 2 - proj.cx
            let my = (p1.sy + p2.sy) / 2 - proj.cy
            // For horizontal edges it matters more to be at the bottom of the screen (+my); for
            // vertical edges, at the left (-mx). A smooth continuous score with no abrupt jumps.
            let score = (abs(dx) * my - abs(dy) * mx) / len
            let edge = Edge(a: CGPoint(x: p1.sx, y: p1.sy), b: CGPoint(x: p2.sx, y: p2.sy), len: len, score: score)
            if score > best.score { best = edge; bestIdx = i }
            if i == lastIdx { last = edge }
        }
        guard best.score > -Double.greatestFiniteMagnitude / 2 else { return [] }

        // Hysteresis: stay on the current edge until a new candidate beats it by a confident margin.
        let chosen: Edge
        if lastIdx >= 0, last.len >= 1, best.score <= last.score + hysteresis {
            chosen = last
            scene.lastEdge[dim] = lastIdx
        } else {
            chosen = best
            scene.lastEdge[dim] = bestIdx
        }

        let ax = Double(chosen.a.x), ay = Double(chosen.a.y)
        let bx = Double(chosen.b.x), by = Double(chosen.b.y)
        let nx = (bx - ax) / chosen.len, ny = (by - ay) / chosen.len

        // The outward normal of the edge (away from the centre of the scene): for the bottom axis
        // (0, 1) — straight down, labels below; for the left axis (-1, 0) — straight left.
        let mx2 = (ax + bx) / 2, my2 = (ay + by) / 2
        var px = -ny, py = nx
        if (mx2 - proj.cx) * px + (my2 - proj.cy) * py < 0 { px = -px; py = -py }

        let szTitle = measure(title, true)
        var cxTi = mx2 + px * (gap + halfSpan(szTitle, px, py))
        var cyTi = my2 + py * (gap + halfSpan(szTitle, px, py))
        var labels: [PlacedLabel] = []

        if a.isOn {
            let szLo = measure(a.loText, false), szHi = measure(a.hiText, false)
            // The low value sits at the minimum end: pushed outward along the normal and shifted
            // inward along the edge, so the label starts at the corner rather than flying off.
            let cxLo = ax + px * (gap + halfSpan(szLo, px, py)) + nx * halfSpan(szLo, nx, ny)
            let cyLo = ay + py * (gap + halfSpan(szLo, px, py)) + ny * halfSpan(szLo, nx, ny)
            let cxHi = bx + px * (gap + halfSpan(szHi, px, py)) - nx * halfSpan(szHi, nx, ny)
            let cyHi = by + py * (gap + halfSpan(szHi, px, py)) - ny * halfSpan(szHi, nx, ny)

            // If the title runs into one of the edge values, it steps aside.
            if abs(px) < 0.5 {
                let minEdgeX = min(cxLo + szLo.width / 2, cxHi + szHi.width / 2)
                let maxEdgeX = max(cxLo - szLo.width / 2, cxHi - szHi.width / 2)
                let leftTi = cxTi - szTitle.width / 2, rightTi = cxTi + szTitle.width / 2
                if leftTi < minEdgeX + 8 || rightTi > maxEdgeX - 8 { cyTi += py * (szTitle.height + 2) }
            } else if abs(py) < 0.5 {
                let minEdgeY = min(cyLo + szLo.height / 2, cyHi + szHi.height / 2)
                let maxEdgeY = max(cyLo - szLo.height / 2, cyHi - szHi.height / 2)
                let topTi = cyTi - szTitle.height / 2, bottomTi = cyTi + szTitle.height / 2
                if topTi < minEdgeY + 8 || bottomTi > maxEdgeY - 8 { cxTi += px * (szTitle.width + 4) }
            }
            labels.append(clamped(a.loText, CGPoint(x: cxLo, y: cyLo), szLo, size, isTitle: false, isDim: true))
            labels.append(clamped(a.hiText, CGPoint(x: cxHi, y: cyHi), szHi, size, isTitle: false, isDim: true))
        }
        labels.append(clamped(title, CGPoint(x: cxTi, y: cyTi), szTitle, size, isTitle: true, isDim: !a.isOn))
        return labels.filter { !$0.text.isEmpty }
    }

    private static func halfSpan(_ s: CGSize, _ vx: Double, _ vy: Double) -> Double {
        (Double(s.width) * abs(vx) + Double(s.height) * abs(vy)) / 2
    }

    /// A caption centred on a point, squeezed within the cloud's bounds: at the edges of the scene
    /// the label otherwise slides under the panel or off the window.
    private static func clamped(_ text: String, _ c: CGPoint, _ sz: CGSize, _ canvas: CGSize,
                                isTitle: Bool, isDim: Bool) -> PlacedLabel {
        let inset = 2.0
        let left = min(max(Double(c.x - sz.width / 2), inset), Double(canvas.width - sz.width) - inset)
        let top = min(max(Double(c.y - sz.height / 2), inset), Double(canvas.height - sz.height) - inset)
        return PlacedLabel(text: text, center: CGPoint(x: left + Double(sz.width) / 2, y: top + Double(sz.height) / 2),
                           isTitle: isTitle, isDim: isDim)
    }
}
