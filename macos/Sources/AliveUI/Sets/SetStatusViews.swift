// Mac-only: how a set's readiness (SetStatus) is worded and drawn — the row mark, the Home tile
// marks and the inspector's status section share these.
import SwiftUI
import AliveCore

/// Wording of a `SetStatus`. Pure so the text can be tested.
enum SetStatusFormat {
    static func label(_ readiness: Readiness) -> String {
        switch readiness {
        case .ready: return SetsStrings.statusReady.s
        case .offline: return SetsStrings.statusOffline.s
        case .missingFiles: return SetsStrings.statusMissingFiles.s
        case .missingPlugins: return SetsStrings.statusMissingPlugins.s
        case .unknown: return SetsStrings.statusUnknown.s
        }
    }

    static func symbol(_ readiness: Readiness) -> String {
        switch readiness {
        case .ready: return "checkmark.circle"
        case .offline: return "externaldrive.badge.xmark"
        case .missingFiles: return "exclamationmark.triangle"
        case .missingPlugins: return "puzzlepiece.extension"
        case .unknown: return "questionmark.circle"
        }
    }

    static func tint(_ readiness: Readiness) -> Color {
        switch readiness {
        case .ready: return Theme.green
        case .offline, .missingFiles, .missingPlugins: return Theme.red
        case .unknown: return Theme.secondaryText
        }
    }

    /// "LaCie RAID 8TB isn't connected (12 files)"; several drives are listed by name.
    static func offlineLine(_ status: SetStatus, separator: String? = nil) -> String? {
        guard status.offlineFiles > 0, !status.offlineVolumes.isEmpty else { return nil }
        let sep = separator ?? (Localizer.shared.lang == .ja ? "、" : ", ")
        return SetsStrings.statusOfflineLine.f(status.offlineVolumes.joined(separator: sep), status.offlineFiles)
    }

    /// "The render is older than the set (exported 2026-05-01)"; nil when it isn't.
    static func staleLine(_ status: SetStatus, calendar: Calendar = .current) -> String? {
        guard status.renderIsStale, let date = status.newestRender else { return nil }
        return SetsStrings.statusStaleLine.f(SetFormat.day(date, calendar: calendar))
    }

    /// Help text for a mark: the readiness plus whatever is behind it.
    static func help(_ status: SetStatus) -> String {
        [label(status.readiness), offlineLine(status), staleLine(status)]
            .compactMap { $0 }.joined(separator: "\n")
    }
}

/// A small icon for a set's readiness, with the wording as help and accessibility label.
struct ReadinessMark: View {
    let status: SetStatus
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: SetStatusFormat.symbol(status.readiness))
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(SetStatusFormat.tint(status.readiness))
            .opacity(status.readiness == .ready ? 0.75 : 1)
            .frame(width: 16, height: 18)
            .help(SetStatusFormat.help(status))
            .accessibilityLabel(SetStatusFormat.label(status.readiness))
    }
}

/// The mark for "the render is older than the set".
struct StaleRenderMark: View {
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
            .frame(width: 16, height: 18)
            .help(SetsStrings.staleRenderHelp.s)
            .accessibilityLabel(SetsStrings.staleRender.s)
    }
}

/// The inspector's "Status:" section.
struct DetailStatus: View {
    let status: SetStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SetsStrings.statusHeading.s).font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
            line(symbol: SetStatusFormat.symbol(status.readiness), tint: SetStatusFormat.tint(status.readiness),
                 text: SetStatusFormat.label(status.readiness), color: Theme.text)
            if let offline = SetStatusFormat.offlineLine(status) {
                line(symbol: "externaldrive.badge.xmark", tint: Theme.red, text: offline, color: Theme.secondaryText)
            }
            if let stale = SetStatusFormat.staleLine(status) {
                line(symbol: "clock.arrow.circlepath", tint: Theme.secondaryText, text: stale, color: Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func line(symbol: String, tint: Color, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(tint).frame(width: 14)
            Text(text).font(Theme.fLabel).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
