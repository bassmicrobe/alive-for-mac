// Port of PaintLegend in nebula/NebulaForm.cs: what the colour channel means, as data.
import Foundation

/// The colour legend is the one channel that does not read without a caption: size and density
/// speak for themselves, while colour is a code.
enum StatLegend: Equatable {
    /// The colour channel is off.
    case off
    /// A continuous gradient between the two edge labels.
    case ramp(gradient: StatGradient, lo: String, hi: String)
    /// Chips for the most populated classes (key, scale, collection).
    case classes([Chip])

    struct Chip: Equatable {
        var name: String
        var rgb: RGB8
        var count: Int
    }

    /// How many chips the legend shows — the rest only clutter it.
    static let maxChips = 10

    static func make(scene: CloudScene) -> StatLegend {
        let axis = scene.color
        guard axis.isOn else { return .off }
        let m = axis.metric
        if m.color == .ramp { return .ramp(gradient: scene.gradient, lo: axis.loText, hi: axis.hiText) }

        var chips: [Chip] = []
        var at: [Int: Int] = [:]
        for s in scene.sets {
            let v = m.value(s)
            if v.isNaN { continue }
            let cls = Int(v)
            if let i = at[cls] { chips[i].count += 1; continue }
            at[cls] = chips.count
            let rgb = m.color == .key ? Palette.key(root: s.scaleRoot, scaleIndex: s.scaleIndex)
                                      : Palette.classColor(cls)
            chips.append(Chip(name: m.text(s), rgb: rgb, count: 1))
        }
        // Most populated first; ties keep first-seen order (stable), so the legend does not shuffle.
        let ordered = chips.enumerated()
            .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
            .map(\.element)
        return .classes(Array(ordered.prefix(maxChips)))
    }
}
