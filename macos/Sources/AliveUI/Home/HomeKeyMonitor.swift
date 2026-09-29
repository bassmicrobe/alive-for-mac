// Mac-only: keyboard for the Home grid (upstream handled keys in the view's WndProc). A local event
// monitor instead of SwiftUI focus: it leaves the search field and every sheet alone.
import AppKit

@MainActor
final class HomeKeyMonitor {
    enum Key: Equatable {
        case `return`, space
        case move(TileNavigation.Direction)
    }

    private var monitor: Any?

    /// Maps a key code (no modifiers held) to a grid key.
    nonisolated static func key(forCode code: UInt16) -> Key? {
        switch code {
        case 36, 76: return .return
        case 49: return .space
        case 123: return .move(.left)
        case 124: return .move(.right)
        case 125: return .move(.down)
        case 126: return .move(.up)
        default: return nil
        }
    }

    /// `handler` returns true to swallow the key. Replaces a previous handler.
    func start(_ handler: @escaping (Key) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  let key = Self.key(forCode: event.keyCode),
                  event.window?.identifier?.rawValue == "main" || event.window?.identifier?.rawValue.hasPrefix("main") == true,
                  !(event.window?.firstResponder is NSText)     // typing in the search field
            else { return event }
            let swallow = MainActor.assumeIsolated { handler(key) }
            return swallow ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
