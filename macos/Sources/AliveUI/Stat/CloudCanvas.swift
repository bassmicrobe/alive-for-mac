// Port of the drawing of CloudView in nebula/Cloud.cs. Upstream splats every dot into a pixel buffer
// of its own to get a soft glow; here SwiftUI's Canvas fills an antialiased disc per dot (upstream's
// default softness is 0.04: almost a solid disc with a thin rim).
import SwiftUI

struct CloudCanvas: View {
    let model: StatModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Read here so the body (and with it the paused state of the timeline) is evaluated again
        // whenever the model asks for a redraw.
        let token = model.frame
        let scene = model.scene
        let animating = scene.isAnimating
        let titles = axisTitles()
        TimelineView(.animation(minimumInterval: nil, paused: !animating)) { timeline in
            Canvas { context, size in
                _ = token
                let wasAnimating = scene.isAnimating
                scene.advance(to: timeline.date)
                scene.project(size: size)
                CloudRenderer.draw(&context, size: size, scene: scene, titles: titles,
                                   time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
                if wasAnimating && !scene.isAnimating {
                    // The motion has come to rest: ask the model for one more body evaluation so
                    // the timeline pauses (never mutate observed state while drawing).
                    Task { @MainActor in model.redraw() }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(StatStrings.cloudLabel.f(model.visibleCount))
    }

    private func axisTitles() -> [String] {
        [(StatStrings.channelX, model.scene.x), (StatStrings.channelY, model.scene.y), (StatStrings.channelZ, model.scene.z)]
            .map { channel, axis in
                StatStrings.axisTitle.f(channel.s, axis.isOn ? axis.metric.title.s : StatStrings.off.s)
            }
    }
}

enum CloudRenderer {
    /// Distant dots are dimmer — without this the cube looks like a flat blob.
    static func fog(_ k: Double) -> Double { 0.42 + 0.58 * min(1, max(0, (k - 0.6) / 0.75)) }

    /// A hovered or selected dot is lit up.
    static func highlight(_ a: Double) -> Double { min(1, a * 1.6 + 0.25) }

    static func draw(_ context: inout GraphicsContext, size: CGSize, scene: CloudScene,
                     titles: [String], time: Double) {
        drawFrame(&context, size: size, scene: scene)
        drawDots(&context, scene: scene, time: time)
        drawMarks(&context, size: size, scene: scene)
        drawAxisLabels(&context, size: size, scene: scene, titles: titles)
    }

    // MARK: cube

    /// The floor and edges of the cube — only so that rotation reads. The lines are almost
    /// invisible on purpose: the scene is about the dots, not about the grid.
    private static func drawFrame(_ context: inout GraphicsContext, size: CGSize, scene: CloudScene) {
        let p = scene.camera.projector(size: size)
        func point(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
            let q = p.project(x, y, z)
            return CGPoint(x: q.sx, y: q.sy)
        }
        var floor = Path()
        for i in 0...8 {
            let t = -1 + Double(i) * 0.25
            floor.move(to: point(t, -1, -1)); floor.addLine(to: point(t, -1, 1))
            floor.move(to: point(-1, -1, t)); floor.addLine(to: point(1, -1, t))
        }
        var edges = Path()
        for i in 0..<4 {
            let a = i & 1 == 0 ? -1.0 : 1.0
            let b = i & 2 == 0 ? -1.0 : 1.0
            edges.move(to: point(-1, a, b)); edges.addLine(to: point(1, a, b))
            edges.move(to: point(a, -1, b)); edges.addLine(to: point(a, 1, b))
            edges.move(to: point(a, b, -1)); edges.addLine(to: point(a, b, 1))
        }
        context.stroke(floor, with: .color(.white.opacity(14.0 / 255)), lineWidth: 1)
        context.stroke(edges, with: .color(.white.opacity(30.0 / 255)), lineWidth: 1)
    }

    // MARK: dots

    private static func drawDots(_ context: inout GraphicsContext, scene: CloudScene, time: Double) {
        let hovered = scene.hovered, selected = scene.selected
        for (i, n) in scene.nodes.enumerated() {
            let r = n.sr
            if r < 0.4 { continue }
            let twinkle = 0.90 + 0.10 * sin(time * 1.68 + n.phase)
            var a = n.alpha * fog(n.depth) * twinkle
            if i == hovered || i == selected { a = highlight(a) }
            if a <= 0.004 { continue }
            let color = Color(.sRGB, red: Double((n.rgb >> 16) & 255) / 255, green: Double((n.rgb >> 8) & 255) / 255,
                              blue: Double(n.rgb & 255) / 255, opacity: a)
            context.fill(Path(ellipseIn: CGRect(x: n.sx - r, y: n.sy - r, width: r * 2, height: r * 2)), with: .color(color))
        }
    }

    // MARK: marks

    /// A ring and a name on the dot under the pointer and on the selected one.
    private static func drawMarks(_ context: inout GraphicsContext, size: CGSize, scene: CloudScene) {
        let nodes = scene.nodes
        if scene.selected >= 0, scene.selected < nodes.count, scene.selected != scene.hovered {
            ring(&context, nodes[scene.selected], opacity: 150.0 / 255, width: 1.1)
        }
        guard scene.hovered >= 0, scene.hovered < nodes.count, let set = scene.hoveredSet else { return }
        let n = nodes[scene.hovered]
        ring(&context, n, opacity: 230.0 / 255, width: 1.6)

        let text = context.resolve(Text(set.name).font(Theme.fTitle).foregroundColor(Theme.text))
        let box = text.measure(in: CGSize(width: 600, height: 40))
        let r = max(n.sr, 6)
        var x = n.sx + r + 10
        if x + box.width > size.width - 8 { x = n.sx - r - 10 - box.width }
        let rect = CGRect(x: x - 6, y: n.sy - box.height / 2 - 2, width: box.width + 12, height: box.height + 4)
        context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2, style: .continuous),
                     with: .color(Theme.bg.opacity(0.78)))
        context.draw(text, at: CGPoint(x: x, y: n.sy), anchor: .leading)
    }

    private static func ring(_ context: inout GraphicsContext, _ n: CloudNode, opacity: Double, width: Double) {
        let r = max(n.sr, 5) + 5
        context.stroke(Path(ellipseIn: CGRect(x: n.sx - r, y: n.sy - r, width: r * 2, height: r * 2)),
                       with: .color(.white.opacity(opacity)), lineWidth: width)
    }

    // MARK: axes

    private static func drawAxisLabels(_ context: inout GraphicsContext, size: CGSize, scene: CloudScene,
                                       titles: [String]) {
        func styled(_ text: String, title: Bool) -> Text {
            Text(text).font(title ? Theme.fLabel : Theme.fBadge)
        }
        let placed = CloudAxisLabels.layout(scene: scene, size: size, titles: titles) { text, isTitle in
            context.resolve(styled(text, title: isTitle)).measure(in: CGSize(width: 400, height: 40))
        }
        for label in placed {
            let color = label.isDim ? Theme.textDim : Theme.text
            let resolved = context.resolve(styled(label.text, title: label.isTitle).foregroundColor(color))
            context.draw(resolved, at: label.center, anchor: .center)
        }
    }
}
