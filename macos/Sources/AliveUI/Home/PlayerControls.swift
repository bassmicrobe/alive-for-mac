// Port of WaveView / VolumeSlider from src/PlayerDialog.cs plus the compact scrub bar of the Home
// strip. Drawn in a Canvas; every control is draggable and keyboard adjustable.
import SwiftUI

enum PlayerFormat {
    /// "0:07", "2:36", "1:02:03".
    static func time(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Makes a position control reachable with the keyboard: it takes focus (with the shared ring),
/// ←/→ move it by 5 %, Shift-←/→ by 10 %, Home/End go to the ends. `isEnabled` false leaves the keys alone.
struct KeyboardScrub: ViewModifier {
    let value: Double
    var cornerRadius: CGFloat = 8
    var isEnabled = true
    let onChange: (Double) -> Void
    @FocusState private var focused: Bool

    static let step = 0.05

    func body(content: Content) -> some View {
        content
            .focusable(isEnabled)
            .focused($focused)
            .focusEffectDisabled()
            .focusRing(focused && isEnabled, cornerRadius: cornerRadius)
            .onKeyPress(keys: [.leftArrow, .rightArrow, .home, .end], phases: [.down, .repeat]) { press in
                guard isEnabled else { return .ignored }
                let big = press.modifiers.contains(.shift) ? 2.0 : 1.0
                switch press.key {
                case .leftArrow: onChange(max(0, value - Self.step * big))
                case .rightArrow: onChange(min(1, value + Self.step * big))
                case .home: onChange(0)
                case .end: onChange(1)
                default: return .ignored
                }
                return .handled
            }
    }
}

/// The envelope of the current render with the played part in a lighter tone. Click or drag to seek.
struct WaveformView: View {
    let waveform: Waveform?
    let progress: Double
    /// Shown instead of the picture while there is none ("reading…").
    let hint: String?
    let onSeek: (Double) -> Void

    private let pad: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous).fill(Theme.sunken)
                if let wave = waveform, wave.ok {
                    Canvas { context, size in draw(wave, in: &context, size: size) }
                } else if let hint {
                    Text(hint).font(Theme.fBody).foregroundStyle(Theme.secondaryText)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let width = max(1, proxy.size.width - pad * 2)
                onSeek(min(1, max(0, (value.location.x - pad) / width)))
            })
        }
        .modifier(KeyboardScrub(value: progress, cornerRadius: Theme.cardR, onChange: onSeek))
        .accessibilityElement()
        .accessibilityLabel(HomeStrings.nowPlayingSeek.s)
        .accessibilityValue("\(Int(progress * 100))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(1, progress + 0.05))
            case .decrement: onSeek(max(0, progress - 0.05))
            @unknown default: break
            }
        }
    }

    private func draw(_ wave: Waveform, in context: inout GraphicsContext, size: CGSize) {
        let inner = CGRect(x: pad, y: pad, width: size.width - pad * 2, height: size.height - pad * 2)
        guard inner.width > 0, inner.height > 0, wave.buckets > 0 else { return }
        let mid = inner.midY
        let half = inner.height / 2
        let playedX = inner.minX + inner.width * progress

        // The zero line, like upstream's thin centre rule.
        context.fill(Path(CGRect(x: inner.minX, y: mid - 0.5, width: inner.width, height: 1)), with: .color(Theme.hairline))

        let columns = Int(inner.width)
        for px in 0..<columns {
            let i = min(wave.buckets - 1, px * wave.buckets / max(1, columns))
            let top = mid - CGFloat(wave.max[i]) * half
            let bottom = mid - CGFloat(wave.min[i]) * half
            let x = inner.minX + CGFloat(px)
            let rect = CGRect(x: x, y: top, width: 1, height: max(1, bottom - top))
            context.fill(Path(rect), with: .color(x <= playedX ? Theme.light : Theme.secondaryText.opacity(0.55)))
        }
        context.fill(Path(CGRect(x: playedX - 0.5, y: inner.minY - 4, width: 1.5, height: inner.height + 8)),
                     with: .color(Theme.lightTop))
    }
}

/// A thin seek bar: track, filled part, a knob that appears on hover.
struct ScrubBar: View {
    let value: Double
    let label: String
    let onChange: (Double) -> Void
    @State private var hovering = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline).frame(height: 4)
                Capsule().fill(Theme.light).frame(width: max(0, w * value), height: 4)
                Circle().fill(Theme.lightTop).frame(width: 12, height: 12)
                    .offset(x: max(0, min(w - 12, w * value - 6)))
                    .opacity(hovering ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { onChange(min(1, max(0, $0.location.x / max(1, w)))) })
            .onHover { hovering = $0 }
            .animation(Theme.hoverAnimation, value: hovering)
        }
        .frame(height: 18)
        .modifier(KeyboardScrub(value: value, cornerRadius: 6, onChange: onChange))
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(1, value + 0.05))
            case .decrement: onChange(max(0, value - 0.05))
            @unknown default: break
            }
        }
    }
}

/// Speaker button + slider. The button mutes and restores the previous level.
struct VolumeControl: View {
    @Binding var volume: Float
    @State private var restore: Float = 0.8

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if volume > 0 { restore = volume; volume = 0 } else { volume = restore }
            } label: {
                IconView(icon: volume <= 0 ? .volume0 : volume < 0.5 ? .volumeLow : .volumeHigh, size: 12)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
            .help(volume > 0 ? HomeStrings.mute.s : HomeStrings.unmute.s)
            .accessibilityLabel(volume > 0 ? HomeStrings.mute.s : HomeStrings.unmute.s)
            ScrubBar(value: Double(volume), label: HomeStrings.volume.s) { volume = Float($0) }
                .frame(width: 96)
        }
    }
}
