// Port of the small controls of the Stat window: DropField, ChannelSwitch, CameraPresetBar
// (nebula/Channels.cs, nebula/NebulaForm.cs) — drawn with SwiftUI in the app's dark style.
import SwiftUI

// MARK: - Drop field

/// A pill with a dim caption on the left and the chosen value beside it; opens a menu of `items`.
struct StatDropField: View {
    let label: String
    let items: [(id: String, title: String)]
    let selection: String
    var isDimmed = false
    let onSelect: (String) -> Void

    @State private var hovering = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Menu {
            ForEach(items, id: \.id) { item in
                Button {
                    onSelect(item.id)
                } label: {
                    if item.id == selection { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(label)
                    .font(Theme.fBody)
                    .foregroundStyle(Theme.textDim)
                    .frame(minWidth: 30, alignment: .leading)
                Text(items.first { $0.id == selection }?.title ?? "")
                    .font(Theme.fBody)
                    .foregroundStyle(isDimmed ? Theme.textDim : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                IconView(icon: .chevronDown, size: 9)
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 14)
            .frame(height: Theme.controlH)
            .background(hovering ? Theme.surfaceHover : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusRing(isFocused, cornerRadius: Theme.controlH / 2)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .accessibilityLabel(label)
        .accessibilityValue(items.first { $0.id == selection }?.title ?? "")
    }
}

// MARK: - Channel switch

/// A square checkbox beside a channel row: it switches a channel on and off without touching the
/// value chosen in the drop-down next to it, so a channel can be brought back without picking its
/// value again.
struct StatChannelSwitch: View {
    let isOn: Bool
    let help: String
    let onToggle: (Bool) -> Void

    @State private var hovering = false

    var body: some View {
        Button { onToggle(!isOn) } label: {
            ZStack {
                if isOn {
                    RoundedRectangle(cornerRadius: 5.6, style: .continuous)
                        .fill(hovering ? Color.white : Theme.light)
                    IconView(icon: .check, size: 10, weight: .bold).foregroundStyle(Theme.onLight)
                } else {
                    RoundedRectangle(cornerRadius: 5.6, style: .continuous)
                        .strokeBorder(hovering ? Theme.text : Theme.textDim, lineWidth: 1.3)
                }
            }
            .frame(width: 18, height: 18)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .animation(Theme.hoverAnimation, value: isOn)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(isOn ? "1" : "0")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Slider

/// A thin slider: a dim track, a light fill, a knob that grows on hover. `value` is 0…1.
struct StatSlider: View {
    let value: Double
    let onChange: (Double) -> Void
    let label: String

    @State private var hovering = false
    @State private var dragging = false
    private let trackH = 4.0

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let x = min(1, max(0, value)) * w
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfacePressed).frame(height: trackH)
                Capsule().fill(dragging || hovering ? Color.white : Theme.light)
                    .frame(width: max(trackH, x), height: trackH)
                Circle()
                    .fill(Color.white)
                    .frame(width: dragging ? 14 : 12, height: dragging ? 14 : 12)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: min(max(0, x - 6), w - 12))
                    .opacity(hovering || dragging ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    dragging = true
                    onChange(min(1, max(0, g.location.x / w)))
                }
                .onEnded { _ in dragging = false })
            .onHover { hovering = $0 }
            .animation(Theme.hoverAnimation, value: hovering)
            .animation(Theme.hoverAnimation, value: dragging)
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(1, value + 0.05))
            case .decrement: onChange(max(0, value - 0.05))
            @unknown default: break
            }
        }
    }
}

// MARK: - Camera presets

/// Four camera presets in one pill, each a small isometric cube: on "Angle" all three faces are
/// even (a free angle), while on Front/Side/Top one face glows — the one normal to the axis the
/// camera looks along in that view. Not a radio button: a click applies the view but is not
/// remembered by a highlight — spin the mouse afterwards and "Front" is no longer true for any of
/// the icons.
struct StatCameraBar: View {
    let onPick: (CameraPreset) -> Void
    @State private var hot: CameraPreset?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CameraPreset.allCases, id: \.self) { preset in
                Button { onPick(preset) } label: {
                    CubeIcon(kind: preset, hot: hot == preset)
                        .frame(width: 34, height: Theme.controlH - 6)
                        .background(hot == preset ? Theme.rowHover : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { inside in hot = inside ? preset : (hot == preset ? nil : hot) }
                .help(help(preset))
                .accessibilityLabel(help(preset))
            }
        }
        .padding(3)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(46.0 / 255), lineWidth: 1))
        .animation(Theme.hoverAnimation, value: hot)
    }

    private func help(_ p: CameraPreset) -> String {
        switch p {
        case .angle: return StatStrings.presetAngle.s
        case .front: return StatStrings.presetFront.s
        case .side: return StatStrings.presetSide.s
        case .top: return StatStrings.presetTop.s
        }
    }
}

/// An isometric cube of three rhombi meeting at one point — a schoolbook projection, but it reads
/// instantly as "a cube" rather than as an abstract hexagon.
private struct CubeIcon: View {
    let kind: CameraPreset
    let hot: Bool

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2, cy = size.height / 2 + size.height * 0.05
            let s = size.height * 0.30 * 1.5
            let o = CGPoint(x: cx, y: cy)
            let v0 = CGPoint(x: cx, y: cy - s), v1 = CGPoint(x: cx + s * 0.866, y: cy - s * 0.5)
            let v2 = CGPoint(x: cx + s * 0.866, y: cy + s * 0.5), v3 = CGPoint(x: cx, y: cy + s)
            let v4 = CGPoint(x: cx - s * 0.866, y: cy + s * 0.5), v5 = CGPoint(x: cx - s * 0.866, y: cy - s * 0.5)
            let dim = Color.white.opacity(hot ? 70.0 / 255 : 46.0 / 255)
            let lit = hot ? Color.white : Theme.light
            let edge = Color.white.opacity(hot ? 170.0 / 255 : 110.0 / 255)
            // The top rhombus looks along Y (Top), the right one along X (Side), the left along Z (Front).
            let faces: [(pts: [CGPoint], on: Bool)] = [
                ([v0, v1, o, v5], kind == .top),
                ([v1, v2, v3, o], kind == .side),
                ([o, v3, v4, v5], kind == .front),
            ]
            for face in faces {
                var path = Path()
                path.addLines(face.pts)
                path.closeSubpath()
                context.fill(path, with: .color(face.on ? lit : dim))
                context.stroke(path, with: .color(edge), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}
