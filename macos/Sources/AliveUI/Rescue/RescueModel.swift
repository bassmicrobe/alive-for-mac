// Mac-only: state of the Rescue sheet (upstream RescueDialog's logic, without the WinForms).
//
// It works semi-automatically: the program prepares a probe copy of the set with plugins
// disabled and opens it, while Live is started and closed by a person. It does not climb into
// somebody else's editor itself — bringing down an unsaved project of theirs along with the probe
// would be exactly what this sheet saves people from. How a probe ended is read from Live's own
// log; the person can also answer by hand.
//
// Nothing is written to disk until the primary button is pressed, and every probe is removed
// when the sheet closes.
import AppKit
import AliveCore
import Foundation
import Observation

@MainActor
@Observable
final class RescueModel {
    enum Phase: Equatable { case idle, loading, ready, preparing, waiting }

    /// Why a row carries a mark.
    enum RowNote: Equatable { case suspect, breaksTheSet }

    @ObservationIgnored unowned let app: AppModel

    private(set) var phase: Phase = .idle
    /// Bumped whenever the (reference-typed) session changes, so views re-read it.
    private(set) var revision = 0
    private(set) var status: RescueStatus?
    /// A tick means "stays enabled", like a device in Live; an unticked plugin is off in the probe.
    private(set) var checked: Set<String> = []
    private(set) var notes: [String: RowNote] = [:]
    private(set) var liveRunning = false
    /// The rescued copy made by the last "Save rescued copy".
    private(set) var produced = ""

    @ObservationIgnored private(set) var session: RescueSession?
    /// Reads Live's log while a probe is out; nil the rest of the time.
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var waitingSince = Date()
    @ObservationIgnored private var generation = 0
    /// The probe being written on the blocking queue; `close()` cancels it.
    @ObservationIgnored private var probeTask: Task<Result<RescueSession.WrittenProbe, Error>, Never>?
    @ObservationIgnored private var ticking = false

    // Seams for tests: Live's processes, Live's logs, and how a probe is opened.
    @ObservationIgnored var isLiveRunning: () -> Bool = { RescueModel.liveIsRunning() }
    @ObservationIgnored var logFiles: () -> [LiveLogFile] = { LiveLog.files() }
    @ObservationIgnored lazy var openProbe: (String) -> Void = { [unowned self] in self.app.openInLive(path: $0) }
    /// Where application launches and quits are announced (tests post to their own centre).
    @ObservationIgnored var workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    /// How often Live's log is read while a probe is out.
    @ObservationIgnored var pollInterval: Duration = .seconds(1)
    /// How long a probe may stay unopened before we stop waiting (upstream: five minutes).
    @ObservationIgnored var giveUpAfter: TimeInterval = 5 * 60

    init(app: AppModel) {
        self.app = app
    }

    // MARK: derived

    var usable: Bool { session.map { $0.error == nil && $0.hasTargets } ?? false }
    var targets: [AlsPluginSlot] { session?.targets ?? [] }
    /// What will actually be disabled in the probe: the plugins with no tick.
    var disabled: [AlsPluginSlot] { targets.filter { !checked.contains($0.uid) } }
    var isWaiting: Bool { phase == .waiting }
    var canEditList: Bool { usable && phase == .ready }
    var canSaveRescued: Bool { usable && phase == .ready && !(session?.rescueSelection().isEmpty ?? true) }

    /// The set's name for the title: the catalog's entry, or made up from the path.
    private(set) var setName = ""

    var runEnabled: Bool {
        switch phase {
        case .ready:
            guard usable else { return true }                    // "Close"
            return !disabled.isEmpty && !liveRunning
        default: return false
        }
    }

    enum RunTitle { case close, open, next, again, waiting }

    var runTitle: RunTitle {
        if phase == .waiting || phase == .preparing { return .waiting }
        guard usable, let s = session else { return .close }
        if s.isFinished { return .again }
        return s.round == 0 ? .open : .next
    }

    var probeFileName: String {
        guard let s = session else { return "" }
        // The real probe may have a different name than the first choice (a free one is picked).
        let actual = s.probePath.isEmpty ? RescueProbe.freePath(for: s.set) : s.probePath
        return (actual as NSString).lastPathComponent
    }

    // MARK: lifecycle

    /// Reads the set and Live's log off the main thread. Safe to call again for another path.
    func open(path: String) async {
        close()
        generation += 1
        let mine = generation
        phase = .loading
        var set = app.catalog.sets.first { $0.path == path } ?? SetEntry()
        if set.path.isEmpty {
            set.path = path
            set.name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        let inventory = app.catalog.index.inventory
        let dir = app.dataDir
        let logs = logFiles
        let entry = set
        let made = await BlockingWork.run { _ in
            RescueSession(set: entry, inventory: inventory, dataDir: dir, logFiles: logs)
        }
        guard mine == generation else { made.cancel(); return }

        session = made
        setName = made.set.name
        checked = Set(made.targets.map(\.uid))          // opens with every box ticked: nothing disabled yet
        liveRunning = isLiveRunning()
        phase = .ready
        revision += 1
        startWatchingLive()
    }

    /// Stops watching and removes any probe: it is an .als inside a project folder, and left
    /// there for good it would one day be opened instead of the real set.
    func close() {
        generation += 1
        stopWatchingLive()
        stopLogPolling()
        // A probe still being written is stopped, and removed when the write returns (see
        // `runProbe`): it lands in the user's project folder and must not outlive the sheet.
        probeTask?.cancel()
        probeTask = nil
        session?.cancel()
        session = nil
        setName = ""
        phase = .idle
        status = nil
        notes = [:]
        checked = []
        produced = ""
    }

    // MARK: the list

    func toggle(_ slot: AlsPluginSlot) {
        guard canEditList else { return }
        if checked.contains(slot.uid) { checked.remove(slot.uid) } else { checked.insert(slot.uid) }
    }

    func setAll(enabled: Bool) {
        guard canEditList else { return }
        checked = enabled ? Set(targets.map(\.uid)) : []
    }

    func applySuggestion() {
        guard canEditList, let s = session else { return }
        setDisabled(s.suggest())
    }

    private func setDisabled(_ off: [AlsPluginSlot]) {
        let drop = Set(off.map(\.uid))
        checked = Set(targets.map(\.uid)).subtracting(drop)
    }

    // MARK: the probe

    /// The primary button: prepare a probe with the unticked plugins disabled and open it in Live.
    func runProbe() async {
        guard phase == .ready, let s = session else { return }
        guard usable else { return }
        let off = disabled
        guard !off.isEmpty, !liveRunning else { return }

        phase = .preparing
        status = nil
        let mine = generation
        // Written on a queue of its own and without touching the session: the views read the
        // session on the main actor. The result is taken over here, on the main actor.
        let task = Task { () -> Result<RescueSession.WrittenProbe, Error> in
            do {
                return .success(try await BlockingWork.run { isCancelled in
                    try s.writeProbe(disable: off, isCancelled: isCancelled)
                })
            } catch { return .failure(error) }
        }
        probeTask = task
        let outcome = await task.value
        guard mine == generation else {
            // The sheet was closed (or another set opened) meanwhile: nobody wants this probe.
            if case .success(let written) = outcome { s.discard(written) }
            return
        }
        probeTask = nil

        switch outcome {
        case .failure(let error):
            if !(error is CancellationError) {
                Diag.fail("rescue: run", error)
                status = .startFailed(Self.message(for: error))
            }
            phase = .ready
        case .success(let written):
            s.commit(written)
            openProbe(written.path)
            phase = .waiting
            waitingSince = Date()
            status = .started(round: s.round, disabled: off.map(\.name))
            startLogPolling()
        }
        revision += 1
    }

    /// The person answers by hand ("It opened" / "It didn't open").
    func answer(opened: Bool) {
        guard phase == .waiting else { return }
        finishProbe(opened: opened, attempt: nil)
    }

    // MARK: watching

    /// Whether Live runs is learnt from the workspace's launch and quit notifications, not by
    /// listing every process each second.
    private func startWatchingLive() {
        stopWatchingLive()
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        workspaceObservers = names.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refreshLiveRunning() }
            }
        }
    }

    private func stopWatchingLive() {
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        workspaceObservers = []
    }

    /// One look at the process list, off the main actor, after an application came or went.
    func refreshLiveRunning() async {
        let mine = generation
        let check = isLiveRunning
        let live = await BlockingWork.run { _ in check() }
        guard mine == generation, live != liveRunning else { return }
        liveRunning = live
    }

    /// Live's log is read only while a probe is out; it stops when the verdict is in.
    private func startLogPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(1))
                guard !Task.isCancelled, let self, self.phase == .waiting else { return }
                await self.tick()
            }
        }
    }

    private func stopLogPolling() {
        poller?.cancel()
        poller = nil
    }

    /// One second of the sheet's life: is Live running, and — while a probe is out — has Live
    /// written its verdict into the log. Reading only what was appended keeps this cheap.
    ///
    /// The process list and the log files are read on the blocking queue, never on the main
    /// actor; the result is applied here if the sheet is still in the state it was asked in.
    func tick() async {
        guard !ticking else { return }
        ticking = true
        defer { ticking = false }
        let mine = generation
        let s = session
        let wasWaiting = phase == .waiting
        let liveCheck = isLiveRunning
        let (live, polled) = await BlockingWork.run { _ in
            (liveCheck(), wasWaiting ? s?.poll() : nil)
        }
        guard mine == generation else { return }
        if live != liveRunning { liveRunning = live }
        guard phase == .waiting, wasWaiting, let s else { return }

        guard let a = polled else {
            // The probe was never opened: the person changed their mind, or Live did not start.
            if Date().timeIntervalSince(waitingSince) > giveUpAfter, !live {
                s.cancel()
                stopLogPolling()
                phase = .ready
                status = .neverOpened
                revision += 1
            }
            return
        }
        if a.result == .running {
            status = .loading(round: s.round, restored: a.restoredCount)
            return
        }
        finishProbe(opened: a.result == .loaded, attempt: a)
    }

    private func finishProbe(opened: Bool, attempt: LoadAttempt?) {
        guard let s = session else { return }
        stopLogPolling()
        s.apply(off: nil, opened: opened, attempt: attempt)
        phase = .ready

        notes = [:]
        for slot in s.suspects { notes[slot.uid] = .suspect }
        if let c = s.culprit { notes[c.uid] = .breaksTheSet }

        if s.isFinished {
            status = nil                                 // the header shows the verdict
        } else if opened {
            status = .opened(round: s.round, suspects: s.suspects.count)
        } else {
            status = .notOpened(round: s.round, stoppedInside: attempt?.hung?.name, left: s.suspects.count)
        }
        setDisabled(s.suggest())
        revision += 1
    }

    // MARK: the outcome

    /// A copy next to the original with the guilty plugin(s) anonymised; the original is never
    /// touched.
    func saveRescued() async {
        guard canSaveRescued, let s = session else { return }
        let pick = s.rescueSelection()
        phase = .preparing
        let mine = generation
        let outcome: Result<String, Error> = await BlockingWork.run { _ in
            Result { try s.writeRescued(disable: pick) }
        }
        // The sheet was closed or another set opened while the copy was written: the file is
        // the person's to keep, but this model's state is no longer about that set.
        guard mine == generation else { return }
        phase = .ready
        switch outcome {
        case .success(let path):
            s.noteSaved(path)
            produced = path
            status = .saved(fileName: (path as NSString).lastPathComponent, disabled: pick.map(\.name))
            app.toast(RescueStrings.toastSaved.f((path as NSString).lastPathComponent))
        case .failure(let error):
            Diag.fail("rescue: save", error)
            status = .saveFailed(Self.message(for: error))
        }
        revision += 1
    }

    // MARK: helpers

    static func message(for error: Error) -> String {
        switch error as? RescueError {
        case .notFoundInSet?: return RescueStrings.errNotFoundInSet.s
        case .nothingToDisable?, .noProbePrepared?: return RescueStrings.errNothingToDisable.s
        case nil: return error.localizedDescription
        }
    }

    /// Whether Ableton Live is running — that is how "still loading" is told from "died", and
    /// why a probe is never started while Live holds an open project.
    nonisolated static func liveIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier?.hasPrefix("com.ableton.live") == true
                || $0.localizedName?.hasPrefix("Ableton Live") == true
        }
    }
}
