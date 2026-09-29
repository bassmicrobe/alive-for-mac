// Port of the update handling in src/SettingsDialog.cs (OnUpdateButton) and src/MainForm.cs
// (CheckUpdatesInBackground, the dot on the gear).
import Foundation
import Observation
import AliveCore

@MainActor
@Observable
final class UpdateModel {
    /// The one model of the app: the Settings window shows it, the main window's gear reads its dot.
    static let shared = UpdateModel()

    enum State: Equatable {
        case idle
        case checking
        case finished(UpdateCheck.Outcome)
    }

    private(set) var state = State.idle
    /// The release the dot on the gear is burning about; empty when there is no dot.
    private(set) var dotVersion = ""

    @ObservationIgnored let currentVersion: String
    @ObservationIgnored private let fetcher: UpdateFetching
    @ObservationIgnored private let today: () -> String
    @ObservationIgnored private var isDailyRunning = false

    /// `currentVersion`: the bundle's short version, "dev" when the binary is not bundled.
    init(currentVersion: String = UpdateModel.bundleVersion(),
         fetcher: UpdateFetching = URLSessionFetcher(),
         today: @escaping () -> String = { UpdateSchedule.dayKey() }) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
        self.today = today
    }

    nonisolated static func bundleVersion(_ bundle: Bundle = .main) -> String {
        let v = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? "dev" : v
    }

    /// Whether the gear carries a dot: a big step newer than us that nobody has looked at yet.
    var hasUnseenUpdate: Bool { !dotVersion.isEmpty }
    var isChecking: Bool { state == .checking }
    var isDevelopmentBuild: Bool { UpdateCheck.parse(currentVersion) == nil }

    /// The newer release a check found (any step, a fix included), if that is what it came to.
    var availableRelease: UpdateCheck.Release? {
        if case .finished(.newer(let release, _)) = state { return release }
        return nil
    }

    /// The page to open for `availableRelease`.
    var releaseURL: URL? { availableRelease.flatMap { URL(string: $0.url) } }

    // MARK: manual check

    /// The button. Asked by hand, so a failure is reported; the background check stays silent about
    /// exactly the same thing — there nobody is waiting for an answer. Any newer release is worth
    /// mentioning here, a fix included; the dot on the gear is the one that keeps to big steps.
    func checkNow(app: AppModel) async {
        guard !isChecking else { return }
        state = .checking
        let outcome = await UpdateCheck.fetch(current: currentVersion, using: fetcher)
        state = .finished(outcome)
        if case .failed = outcome { return }
        stampToday(app)
        // Shown right here, so the gear has nothing left to say about it.
        if case .newer(let release, _) = outcome {
            dotVersion = ""
            app.mutateSettings { $0.seenUpdate = release.version }
        }
    }

    // MARK: daily check

    /// After the first scan of a session — never at startup, so it does not compete with the thing
    /// people opened the program for. A no-op unless the daily check is on and today's has not run.
    func dailyCheckIfDue(app: AppModel) {
        guard isDue(app) else { return }
        Task { [weak app] in
            guard let app else { return }
            await runDailyCheck(app: app)
        }
    }

    func isDue(_ app: AppModel) -> Bool {
        !isChecking && !isDailyRunning && UpdateSchedule.isDue(enabled: app.settings.checkUpdates,
                                            lastCheck: app.settings.lastUpdateCheck, today: today())
    }

    /// The check itself, awaitable (tests). Silent about failures: no dot, no message.
    func runDailyCheck(app: AppModel) async {
        guard isDue(app) else { return }
        isDailyRunning = true
        defer { isDailyRunning = false }
        let outcome = await UpdateCheck.fetch(current: currentVersion, using: fetcher)
        // The day is written down even when the answer was no use: retrying on every scan of a
        // machine with no network would be a request a minute.
        stampToday(app)
        if case .failed = outcome { return }
        if UpdateSchedule.shouldLightDot(outcome, seen: app.settings.seenUpdate),
           case .newer(let release, _) = outcome {
            dotVersion = release.version
        }
        if !isChecking { state = .finished(outcome) }
    }

    private func stampToday(_ app: AppModel) {
        let day = today()
        app.mutateSettings { $0.lastUpdateCheck = day }
    }

    // MARK: the dot

    /// The dot has done its job the moment the settings are opened: whatever it was about is on the
    /// first screen now. We write down which release it was, so the same one does not light it
    /// again tomorrow.
    func markSeen(app: AppModel) {
        guard !dotVersion.isEmpty else { return }
        let seen = dotVersion
        dotVersion = ""
        app.mutateSettings { $0.seenUpdate = seen }
    }
}
