// Port of src/Glass*.cs (Acrylic "glass"): NSVisualEffectView behind the content, off by default.
import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blending
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Makes the hosting window see-through (or opaque again) so `VisualEffectBackground` can blur
/// what is behind it. Placed as a zero-size background of the window content.
struct WindowTransparency: NSViewRepresentable {
    let isTransparent: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: view.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = !isTransparent
        window.backgroundColor = isTransparent ? .clear : NSColor(Theme.bg)
    }
}
