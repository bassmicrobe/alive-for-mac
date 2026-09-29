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
        coordinator.paths = rows.map(\.path)
        guard request.serial != coordinator.handled, let path = request.path else { return }
        coordinator.handled = request.serial
        coordinator.attempt(path: path, serial: request.serial, view: view, tries: 0)
    }

    final class Coordinator {
        var handled = 0
        /// The rows as of the latest update: a later layout pass may have changed them.
        var paths: [String] = []

        /// Centres `path`'s row once the table has laid out and applied the selection. The table is
        /// still being sized and filled on the first passes (the inspector opens beside it), so a
        /// scroll done too early lands short: check the row really is on screen, else try again.
        func attempt(path: String, serial: Int, view: NSView?, tries: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + (tries == 0 ? 0.08 : 0.25)) { [weak self, weak view] in
                guard let self, self.handled == serial,
                      let table = view?.window.flatMap({ TableScrollBridge.findTable(in: $0.contentView) }),
                      let row = self.paths.firstIndex(of: path), row < table.numberOfRows else { return }
                TableScrollBridge.center(row: row, in: table)
                let onScreen = table.visibleRect.contains(table.rect(ofRow: row))
                if (!onScreen || !table.selectedRowIndexes.contains(row)) && tries < Self.maxTries {
                    self.attempt(path: path, serial: serial, view: view, tries: tries + 1)
                }
            }
        }

        private static let maxTries = 6
    }

    /// Scrolls so the row sits in the middle of the visible area (as far as the ends allow).
    static func center(row: Int, in table: NSTableView) {
        guard let scroll = table.enclosingScrollView else { table.scrollRowToVisible(row); return }
        let clip = scroll.contentView
        table.layoutSubtreeIfNeeded()
        let rect = table.rect(ofRow: row)
        let top = table.headerView?.frame.height ?? 0
        let visibleHeight = clip.bounds.height - top
        let target = rect.midY - top - visibleHeight / 2
        let maxY = max(0, table.frame.height - clip.bounds.height)
        let y = min(max(-clip.contentInsets.top, target), maxY)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scroll.reflectScrolledClipView(clip)
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
