// Mac-only: SwiftUI's Table has no "scroll to row" on macOS 14, so this finds the table's
// NSTableView and calls `scrollRowToVisible` when `SetsModel.select(path:)` asks for it.
import AppKit
import SwiftUI
import AliveCore

struct TableScrollBridge: NSViewRepresentable {
    let request: SetsModel.ScrollRequest
    /// The rows as the table shows them right now (heads and unfolded versions).
    let rows: [SetEntry]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        guard request.serial != coordinator.handled, let path = request.path else { return }
        coordinator.handled = request.serial
        let paths = rows.map(\.path)
        // The table lays a just-unfolded folder out on the next pass: scroll after it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak view] in
            guard let table = view?.window.flatMap({ Self.findTable(in: $0.contentView) }),
                  let row = paths.firstIndex(of: path), row < table.numberOfRows else { return }
            table.scrollRowToVisible(row)
        }
    }

    final class Coordinator {
        var handled = 0
    }

    /// The biggest NSTableView below `root` (the window has one list at a time).
    static func findTable(in root: NSView?) -> NSTableView? {
        guard let root else { return nil }
        var best: NSTableView?
        var stack = [root]
        while let view = stack.popLast() {
            if let table = view as? NSTableView,
               table.bounds.width * table.bounds.height > (best.map { $0.bounds.width * $0.bounds.height } ?? 0) {
                best = table
            }
            stack.append(contentsOf: view.subviews)
        }
        return best
    }
}
