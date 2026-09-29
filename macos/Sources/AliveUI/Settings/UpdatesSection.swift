// Port of the update rows of src/SettingsDialog.cs: the version line with its button, the daily check.
// SettingsView embeds this section.
import SwiftUI
import AppKit
import AliveCore

struct UpdatesSection: View {
    @Environment(AppModel.self) private var app
    private let updates = UpdateModel.shared

    var body: some View {
        @Bindable var prefs = app.prefs
        Section(SettingsStrings.updatesTitle.s) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(versionLine).font(Theme.fBody).foregroundStyle(Theme.text)
                    Text(statusLine)
                        .font(Theme.fSmall)
                        .foregroundStyle(statusIsProblem ? Theme.errorText : Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(statusLine)
                }
                Spacer(minLength: 8)
                if updates.isChecking {
                    ProgressView().controlSize(.small).accessibilityLabel(UpdateStrings.checking.s)
                }
                PillButton(title: buttonTitle, kind: updates.releaseURL == nil ? .quiet : .primary, action: pressButton)
                    .disabled(updates.isChecking)
            }
            Toggle(UpdateStrings.dailyToggle.s, isOn: $prefs.dailyUpdateCheck)
            Text(UpdateStrings.dailyHelp.s)
                .font(Theme.fSmall).foregroundStyle(Theme.secondaryText)
        }
        // The dot on the gear has done its job the moment the settings are open (upstream: ShowSettings).
        .onAppear { updates.markSeen(app: app) }
    }

    // MARK: text

    private var versionLine: String {
        updates.isDevelopmentBuild ? UpdateStrings.developmentBuild.s : UpdateStrings.currentVersion.f(updates.currentVersion)
    }

    private var buttonTitle: String {
        updates.releaseURL == nil ? UpdateStrings.checkButton.s : UpdateStrings.openRelease.s
    }

    private var statusIsProblem: Bool {
        if case .finished(.failed) = updates.state { return true }
        return false
    }

    /// The grey line under the button — the only place the check speaks.
    private var statusLine: String {
        switch updates.state {
        case .idle: return lastChecked
        case .checking: return UpdateStrings.checking.s
        case .finished(let outcome): return Self.describe(outcome)
        }
    }

    static func describe(_ outcome: UpdateCheck.Outcome) -> String {
        switch outcome {
        case .upToDate: return UpdateStrings.upToDate.s
        case .noReleases: return UpdateStrings.noReleases.s
        case .failed(.rateLimited): return UpdateStrings.failedRateLimited.s
        case .failed(.unreachable): return UpdateStrings.failedUnreachable.s
        case .failed(.unexpectedAnswer): return UpdateStrings.failedUnexpected.s
        case .newer(let release, _):
            return release.name.isEmpty || release.name == release.version
                ? UpdateStrings.newerVersion.f(release.version)
                : UpdateStrings.newerVersionNamed.f(release.version, release.name)
        }
    }

    private var lastChecked: String {
        let raw = app.settings.lastUpdateCheck
        guard !raw.isEmpty else { return UpdateStrings.neverChecked.s }
        return UpdateStrings.lastChecked.f(Self.dayText(raw))
    }

    /// "2026-03-07" in the reader's language; the raw text when it is not a date.
    static func dayText(_ raw: String, locale: Locale = Localizer.shared.locale) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: raw) else { return raw }
        return date.formatted(.dateTime.year().month().day().locale(locale))
    }

    // MARK: action

    /// The button asks, and once something has been found it opens the page instead. Two jobs on one
    /// button because they are one errand: the answer to "is there anything new" is either "no" or a
    /// place to go.
    private func pressButton() {
        if let url = updates.releaseURL {
            NSWorkspace.shared.open(url)
        } else {
            Task { await updates.checkNow(app: app) }
        }
    }
}
