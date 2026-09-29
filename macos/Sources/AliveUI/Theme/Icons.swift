// Port of the `Glyph` enum in src/Icons.cs: same names, drawn with SF Symbols instead of GDI+ paths.
import SwiftUI

enum AppIcon: CaseIterable {
    case folder, refresh, settings, minimize, maximize, close, closeFullscreen
    case filters, magnifier, chevronDown, sortUp, sortDown, check
    case play, pause
    case volume0, volumeLow, volumeHigh
    case star, starFill, plus
    case nextSet, prevSet, nextTrack, prevTrack, openPlaylist, viewList
    case note, tag, nebula, keyboard, calendar, hiddenBtnsOpen, hiddenBtnsClose, wave
    case dice1, dice2, dice3, dice4, dice5, dice6
    /// Mac-only additions (Stat button, help, info).
    case stat, help, info, warning

    static let mute = AppIcon.volume0
    static let volume = AppIcon.volumeHigh
    static let dice = AppIcon.dice1

    var symbol: String {
        switch self {
        case .folder: return "folder"
        case .refresh: return "arrow.clockwise"
        case .settings: return "gearshape"
        case .minimize: return "minus"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .close: return "xmark"
        case .closeFullscreen: return "arrow.down.right.and.arrow.up.left"
        case .filters: return "line.3.horizontal.decrease"
        case .magnifier: return "magnifyingglass"
        case .chevronDown: return "chevron.down"
        case .sortUp: return "chevron.up"
        case .sortDown: return "chevron.down"
        case .check: return "checkmark"
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .volume0: return "speaker.slash.fill"
        case .volumeLow: return "speaker.wave.1.fill"
        case .volumeHigh: return "speaker.wave.3.fill"
        case .star: return "star"
        case .starFill: return "star.fill"
        case .plus: return "plus"
        case .nextSet: return "forward.end.fill"
        case .prevSet: return "backward.end.fill"
        case .nextTrack: return "forward.fill"
        case .prevTrack: return "backward.fill"
        case .openPlaylist: return "music.note.list"
        case .viewList: return "list.bullet"
        case .note: return "note.text"
        case .tag: return "tag"
        case .nebula: return "sparkles"
        case .keyboard: return "keyboard"
        case .calendar: return "calendar"
        case .hiddenBtnsOpen: return "chevron.left"
        case .hiddenBtnsClose: return "chevron.right"
        case .wave: return "waveform"
        case .dice1: return "die.face.1"
        case .dice2: return "die.face.2"
        case .dice3: return "die.face.3"
        case .dice4: return "die.face.4"
        case .dice5: return "die.face.5"
        case .dice6: return "die.face.6"
        case .stat: return "chart.bar"
        case .help: return "questionmark"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        }
    }

    var image: Image { Image(systemName: symbol) }
}

/// An `AppIcon` at a consistent size and weight.
struct IconView: View {
    let icon: AppIcon
    var size: CGFloat = 13
    var weight: Font.Weight = .medium

    var body: some View {
        icon.image
            .font(.system(size: size, weight: weight))
            .imageScale(.medium)
    }
}
