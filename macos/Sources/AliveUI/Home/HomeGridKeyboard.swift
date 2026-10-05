// Mac-only: keys handled by a focused project tile. Keeping the mapping separate makes it
// testable without a window-wide event monitor that steals keys from buttons and seek controls.
import SwiftUI

enum HomeGridKeyboard {
    enum Action: Equatable {
        case open, play
        case move(TileNavigation.Direction)
    }

    static let keys: Set<KeyEquivalent> = [.return, .space, .leftArrow, .rightArrow, .downArrow, .upArrow]

    static func action(for key: KeyEquivalent, modifiers: EventModifiers = [],
                       phase: KeyPress.Phases = .down) -> Action? {
        guard modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return nil }
        switch key {
        // Holding Return or Space must not launch Live repeatedly or keep toggling playback.
        case .return: return phase == .down ? .open : nil
        case .space: return phase == .down ? .play : nil
        case .leftArrow: return .move(.left)
        case .rightArrow: return .move(.right)
        case .downArrow: return .move(.down)
        case .upArrow: return .move(.up)
        default: return nil
        }
    }
}
