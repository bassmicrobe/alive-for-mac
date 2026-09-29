// Mac-only: the words of the Rescue sheet, built from typed core state (upstream RescueDialog's
// Describe/Hint/AfterProbe strings). Pure and localized at call time, so a language switch shows
// at once and the wording is unit-testable.
import AliveCore
import Foundation

/// What the sheet is telling the person right now, besides what the session itself knows.
enum RescueStatus: Equatable {
    case started(round: Int, disabled: [String])
    case loading(round: Int, restored: Int)
    case opened(round: Int, suspects: Int)
    case notOpened(round: Int, stoppedInside: String?, left: Int)
    case neverOpened
    case startFailed(String)
    case saved(fileName: String, disabled: [String])
    case saveFailed(String)
}

enum RescueText {
    /// "Serum", "Serum, Pro-Q 3", "5 plugins" (upstream `Describe`).
    static func describe(_ names: [String]) -> String {
        switch names.count {
        case 0: return RescueStrings.describeNothing.s
        case 1...3: return names.joined(separator: ", ")
        default: return RescueStrings.plugins(names.count)
        }
    }

    /// "28 Mar 2026, 22:45" in the UI language.
    static func when(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))
    }

    /// The paragraph on top when nothing more specific is going on: what is known about the set.
    static func header(_ s: RescueSession) -> String {
        if let e = s.error { return RescueStrings.readError.f(e) }
        if s.targets.isEmpty { return RescueStrings.noPlugins.s }
        if s.isFinished { return verdict(s) }
        guard let h = s.history else { return RescueStrings.logNone.s }

        let when = when(h.started)
        if h.result == .loaded {
            return RescueStrings.logLoaded.f(when, RescueStrings.plugins(h.restoredCount))
        }
        var text: String
        if let hung = h.hung {
            text = RescueStrings.logStops.f(hung.format, hung.name, when, RescueStrings.plugins(h.restoredCount))
        } else {
            text = RescueStrings.logUnfinished.f(when)
        }
        if h.priorCrashDetected != nil { text += " " + RescueStrings.logCrashed.s }
        return text
    }

    static func status(_ st: RescueStatus) -> String {
        switch st {
        case .started(let round, let names):
            return RescueStrings.statusStarted.f(round, describe(names))
        case .loading(let round, let restored):
            return RescueStrings.statusLoading.f(round, RescueStrings.plugins(restored))
        case .opened(let round, let suspects):
            return RescueStrings.statusOpened.f(round, RescueStrings.plugins(suspects))
        case .notOpened(let round, let stopped, let left):
            let where_ = stopped.map { RescueStrings.stoppedInside.f($0) } ?? ""
            return RescueStrings.statusNotOpened.f(round, where_, RescueStrings.plugins(left))
        case .neverOpened: return RescueStrings.statusNeverOpened.s
        case .startFailed(let e): return RescueStrings.statusStartFailed.f(e)
        case .saved(let name, let names): return RescueStrings.statusSaved.f(name, describe(names))
        case .saveFailed(let e): return RescueStrings.statusSaveFailed.f(e)
        }
    }

    /// The finished investigation's verdict as a sentence.
    static func verdict(_ s: RescueSession) -> String {
        switch s.verdict {
        case .culprit:
            return RescueStrings.verdictCulprit.f(s.culprit?.format ?? "", s.culprit?.name ?? "")
        case .group: return RescueStrings.verdictGroup.f(describe((s.working ?? []).map(\.name)))
        case .notPlugins: return RescueStrings.verdictNotPlugins.s
        default: return ""
        }
    }

    /// The line under the list.
    static func hint(usable: Bool, waiting: Bool, liveRunning: Bool, disabledCount: Int, probeFileName: String) -> String {
        if waiting { return RescueStrings.hintWaiting.s }
        guard usable else { return "" }
        if liveRunning { return RescueStrings.hintCloseLive.s }
        if disabledCount == 0 { return RescueStrings.hintUntick.s }
        return RescueStrings.hintProbe.f(probeFileName)
    }

    /// ONE line for every plugin Live refused in the attempt, however many times the log repeats
    /// it; nil when there were none. The per-plugin list goes into a disclosure.
    static func refusedSummary(_ groups: [PluginFailureGroup]) -> String? {
        guard !groups.isEmpty else { return nil }
        return RescueStrings.refusedSummary.f(RescueStrings.plugins(groups.count))
    }

    static func refusedLine(_ g: PluginFailureGroup) -> String {
        RescueStrings.refusedLine.f(g.format, g.name, g.count)
    }
}
