// Port of src/RescueSession.cs (RescueSession, RescueVerdict). The trail is typed (the UI
// localizes it); the report text is built by the UI.
import Foundation

/// How the whole investigation ended.
public enum RescueVerdict: Equatable, Sendable {
    /// Still searching.
    case none
    /// The set would not open even with everything disabled — it is not the plugins.
    case notPlugins
    /// Exactly one is guilty, and it is in `culprit`.
    case culprit
    /// Several are guilty; the set whose disabling helps is known (`working`).
    case group
    /// There have been no probes yet.
    case noProbeYet
}

/// One line of the investigation's progress.
public enum RescueTrailEntry: Equatable, Sendable {
    case logOpenedFine(Date)
    case logStoppedInside(format: String, name: String, Date)
    case logUnfinished(Date)
    case probe(round: Int, disabled: [String])
    case opened(disabledCount: Int)
    case didNotOpen(stoppedInside: String?)
    case verdictNotPlugins
    case verdictGroup(disabled: [String])
    case verdictCulprit(format: String, name: String)
    case saved(fileName: String)
}

public enum RescueError: Error, Equatable {
    case nothingToDisable
    case notFoundInSet
    case noProbePrepared
    case noFreeIdentifier
}

/// The investigation of one set that will not open.
///
/// The search logic rests on a single assumption: ONE plugin breaks it. Each probe is then an
/// answer to the question "is the culprit inside the disabled set?":
///
///     opened     → the culprit is among the disabled → suspects ∩= disabled
///     not opened → the culprit is not among them     → suspects −= disabled
///
/// Any set works that way, not just an even half — which means a person can tick the boxes
/// themselves, and the investigation will take that into account rather than lose its footing.
///
/// The assumption is testable: if not a single suspect is left, more than one is guilty, and
/// instead of a name the working set is given — the one whose disabling opened the set. That is
/// always true, even when there is no pretty answer.
///
/// One operation at a time (`prepare`, `poll`, `apply` are called by one model, one after the
/// other); the class is marked Sendable only so a model can run the slow parts off the main
/// thread. Those slow parts (`writeProbe`, `poll`, `writeRescued`) change no state that a view
/// reads: state (`round`, `trail`, `probePath` …) is changed only by `commit`, `apply` and the
/// other quick methods, which the model calls on the main actor. `poll` alone touches its own
/// log bookkeeping and the probe path, under `stateLock`.
public final class RescueSession: @unchecked Sendable {
    public private(set) var set: SetEntry
    public let info: AlsInfo
    public let targets: [AlsPluginSlot]
    public let unaddressable: Int
    /// The .als itself would not read: no plugin has anything to do with it.
    public let error: String?

    /// What Live's log remembers about previous attempts to open this set.
    public var history: LoadAttempt?
    public var historySuspect: AlsPluginSlot?

    /// Who else may be guilty.
    public private(set) var suspects: [AlsPluginSlot] = []
    /// The smallest known set whose disabling opened the set.
    public private(set) var working: [AlsPluginSlot]?
    public private(set) var verdict: RescueVerdict = .noProbeYet
    public private(set) var culprit: AlsPluginSlot?
    public private(set) var round = 0
    public private(set) var probePath: String {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _probePath }
        set { stateLock.lock(); _probePath = newValue; stateLock.unlock() }
    }
    public private(set) var probeDisabled: [AlsPluginSlot] = []
    public private(set) var probeStarted = Date.distantPast
    public private(set) var trail: [RescueTrailEntry] = []

    private let stateLock = NSLock()
    private var _probePath = ""
    private let inventory: PluginInventory?
    private let dataDir: String
    private let logProvider: () -> [LiveLogFile]
    private var logs: [String: LiveLogFile] = [:]

    /// Reads the set and asks Live's log about it (heavy on big sets and big logs — call off the
    /// main thread). `dataDir` holds the probe journal.
    public convenience init(set: SetEntry, inventory: PluginInventory?, dataDir: String,
                            logFiles: @escaping () -> [LiveLogFile] = { LiveLog.files() }) {
        self.init(set: set, info: AlsFile.read(path: set.path), inventory: inventory, dataDir: dataDir,
                  logFiles: logFiles)
    }

    /// The same with an already-read `AlsInfo` (simulations, tests).
    public init(set: SetEntry, info: AlsInfo, inventory: PluginInventory?, dataDir: String,
                logFiles: @escaping () -> [LiveLogFile] = { LiveLog.files() }) {
        self.set = set
        self.info = info
        self.inventory = inventory
        self.dataDir = dataDir
        self.logProvider = logFiles
        if let err = info.error, !err.isEmpty {
            error = err
            targets = []
            unaddressable = 0
            return
        }
        error = nil
        // A minimal SetEntry may not have known what the .als says.
        if self.set.creator.isEmpty { self.set.creator = info.creator }
        targets = AlsPatch.targets(info)
        unaddressable = AlsPatch.unaddressable(info)
        suspects = targets
        diagnose()
    }

    public var hasTargets: Bool { !targets.isEmpty }
    public var isFinished: Bool { verdict == .culprit || verdict == .notPlugins || verdict == .group }

    // MARK: diagnosis

    /// Asks Live's log before any probes. If the set has crashed already, Live recorded which
    /// plugin it broke off on — and the first probe can start with that one straight away.
    private func diagnose() {
        history = LiveLog.lastAttempt(for: set.path, in: logProvider())
        guard let h = history else { return }
        let hung = h.hung
        if let hung { historySuspect = match(hung.name) }

        if h.result == .loaded {
            note(.logOpenedFine(h.started))
        } else if let hung {
            note(.logStoppedInside(format: hung.format, name: hung.name, h.started))
        } else {
            note(.logUnfinished(h.started))
        }
    }

    /// A name from the log turned into a plugin of the set. Exactly first: both the log and the
    /// .als take the name from the same place, so it usually matches letter for letter. The
    /// lenient comparison is for the "Serum_x64" against "Serum (64 Bit)" case.
    public func match(_ name: String) -> AlsPluginSlot? {
        guard !name.isEmpty else { return nil }
        if let s = targets.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return s }
        let norm = PluginInventory.normalize(name)
        guard !norm.isEmpty else { return nil }
        return targets.first { PluginInventory.normalize($0.name) == norm }
    }

    // MARK: what to probe

    /// What to suggest disabling in the next probe. A suggestion rather than an order: a person
    /// edits the boxes themselves, and `apply` copes with any set.
    public func suggest() -> [AlsPluginSlot] {
        guard !targets.isEmpty else { return [] }

        // The first probe: if the log has already named a suspect — that one alone, right away.
        // Guessed right and the investigation ends on the very first probe rather than the fifth.
        guard working != nil else {
            if round == 0, let s = historySuspect { return [s] }
            return targets
        }
        if suspects.count > 1 { return Array(suspects[0..<(suspects.count / 2)]) }
        if suspects.count == 1 { return suspects }
        return working ?? []
    }

    /// A probe that has been written to disk but not yet taken into the session's state.
    public struct WrittenProbe: @unchecked Sendable {
        public let path: String
        let disabled: [AlsPluginSlot]
        let logs: [String: LiveLogFile]
    }

    /// Assembles a probe copy with the chosen plugins disabled and returns its path; throws —
    /// failing to write a probe means failing to start, and that cannot be kept quiet. The
    /// original is only ever read.
    public func prepare(disable: [AlsPluginSlot], isCancelled: () -> Bool = { false }) throws -> String {
        let written = try writeProbe(disable: disable, isCancelled: isCancelled)
        commit(written)
        return written.path
    }

    /// The slow half of `prepare`: writes the probe file (and the journal line) and remembers
    /// where Live's logs end now. Changes no session state — safe off the main thread; the
    /// caller hands the result to `commit`, or to `discard` if it is no longer wanted.
    public func writeProbe(disable: [AlsPluginSlot], isCancelled: () -> Bool = { false }) throws -> WrittenProbe {
        guard !disable.isEmpty else { throw RescueError.nothingToDisable }

        // A name nobody is using: an existing file at the probe path is never touched.
        let probe = RescueProbe.freePath(for: set)
        // The journal first, the disk second: a crash can happen in between.
        RescueProbe.remember(probe, dir: dataDir)
        let patched: Int
        do {
            patched = try AlsPatch.neutralize(src: set.path, dst: probe, uids: disable.map(\.uid),
                                              inventory: inventory, isCancelled: isCancelled)
        } catch {
            // `neutralize` removes what it created; a name it could not create is not ours.
            RescueProbe.forgetIfGone(probe, dir: dataDir)
            throw error
        }
        if patched == 0 {
            RescueProbe.drop(probe, dir: dataDir)       // we created it a moment ago
            throw RescueError.notFoundInSet
        }
        if isCancelled() {
            // Cancelled while the probe was being finished: it must not outlive the request.
            RescueProbe.drop(probe, dir: dataDir)
            throw CancellationError()
        }

        // Live's logs are read from their current end: whatever came before the probe has
        // already been parsed in `diagnose`.
        var logs: [String: LiveLogFile] = [:]
        for f in logProvider() {
            f.skipToEnd()
            logs[f.path] = f
        }
        return WrittenProbe(path: probe, disabled: disable, logs: logs)
    }

    /// The quick half of `prepare`: the written probe becomes the session's current one.
    public func commit(_ written: WrittenProbe) {
        cancel()
        stateLock.lock()
        _probePath = written.path
        logs = written.logs
        stateLock.unlock()
        probeDisabled = written.disabled
        probeStarted = Date()
        round += 1
        note(.probe(round: round, disabled: written.disabled.map(\.name)))
    }

    /// Removes a probe that `writeProbe` made but nobody took over (the sheet was closed while
    /// it was being written).
    public func discard(_ written: WrittenProbe) {
        RescueProbe.drop(written.path, dir: dataDir)
    }

    /// Removes the current probe from disk and journal.
    public func cancel() {
        guard !probePath.isEmpty else { return }
        RescueProbe.drop(probePath, dir: dataDir)
        probePath = ""
        probeDisabled = []
    }

    // MARK: the outcome of a probe

    /// What Live's logs say about the current probe; nil means Live has not opened it yet. The
    /// files are re-scanned every time: which Live version a person will start is not known in
    /// advance, and a fresh install may not have had a Log.txt until now.
    ///
    /// Reads files, so the model calls it off the main thread; the bookkeeping is under the lock.
    public func poll() -> LoadAttempt? {
        let probe = probePath
        guard !probe.isEmpty else { return nil }
        let appeared = logProvider()
        stateLock.lock(); defer { stateLock.unlock() }
        for f in appeared where logs[f.path] == nil { logs[f.path] = f }   // has only just appeared

        var best: LoadAttempt?
        for f in logs.values {
            for a in f.readNew() where LiveLog.samePath(a.document, probe) {
                if best == nil || a.started >= best!.started { best = a }
            }
        }
        return best
    }

    /// Takes the outcome of a probe into account and narrows the circle. `opened`: the set
    /// opened in full.
    ///
    /// The disabled set is passed explicitly rather than taken from `probeDisabled`: the course
    /// of the investigation can then be run through without a single file on disk and without
    /// Live — which is how convergence is checked (upstream tools/RescueTest.cs `simulate`).
    public func apply(off: [AlsPluginSlot]?, opened: Bool, attempt: LoadAttempt?) {
        let off = off ?? probeDisabled
        cancel()

        if opened {
            note(.opened(disabledCount: off.count))
            if working == nil || off.count < working!.count { working = off }
            suspects = suspects.filter { Self.contains(off, $0) }
        } else {
            let stopped = attempt?.hung
            note(.didNotOpen(stoppedInside: stopped?.name))

            // The log named the plugin it broke off on: that one is guilty, and there is no
            // point halving further. The hint is taken only if that plugin really was enabled —
            // otherwise it is about something else.
            if let stopped, let named = match(stopped.name),
               !Self.contains(off, named), Self.contains(suspects, named) {
                suspects = [named]
            } else {
                suspects = suspects.filter { !Self.contains(off, $0) }
            }
        }
        settle(opened: opened, off: off)
    }

    private func settle(opened: Bool, off: [AlsPluginSlot]) {
        // Everything that could be was disabled and it still would not open — not the plugins.
        if !opened, working == nil, off.count == targets.count {
            verdict = .notPlugins
            note(.verdictNotPlugins)
            return
        }
        guard let working else { verdict = .none; return }

        if suspects.isEmpty {
            // Empty means more than one plugin is guilty, and there will be no pretty name.
            // `working`, on the other hand, has been proved in practice: with it the set opened.
            verdict = .group
            note(.verdictGroup(disabled: working.map(\.name)))
            return
        }
        if opened, off.count == 1, suspects.count == 1 {
            culprit = suspects[0]
            verdict = .culprit
            note(.verdictCulprit(format: suspects[0].format, name: suspects[0].name))
            return
        }
        verdict = .none
    }

    // MARK: the rescued copy

    /// What to disable in the rescued copy: the culprit that was found, or, if there is more
    /// than one, the whole proven set.
    public func rescueSelection() -> [AlsPluginSlot] {
        if let culprit { return [culprit] }
        return working ?? []
    }

    /// `<set folder>/<set name> (rescued).als`
    public var rescuedPath: String {
        (set.directory as NSString).appendingPathComponent(set.name + " (rescued).als")
    }

    /// A copy next to the original with the guilty plugin anonymised. The original is not
    /// touched on any outcome: it will come in handy again when the plugin is updated or
    /// reinstalled. An existing file is never overwritten ("… (rescued) 2.als").
    public func saveRescued(disable: [AlsPluginSlot]) throws -> String {
        let dst = try writeRescued(disable: disable)
        noteSaved(dst)
        return dst
    }

    /// The slow half of `saveRescued`: writes the copy, changes no session state (off the main
    /// thread); `noteSaved` puts it into the trail.
    public func writeRescued(disable: [AlsPluginSlot]) throws -> String {
        guard !disable.isEmpty else { throw RescueError.nothingToDisable }
        let dst = Self.unique(rescuedPath)
        let patched = try AlsPatch.neutralize(src: set.path, dst: dst,
                                              uids: disable.map(\.uid), inventory: inventory)
        if patched == 0 {
            try FileManager.default.removeItem(atPath: dst)
            throw RescueError.notFoundInSet
        }
        return dst
    }

    public func noteSaved(_ path: String) {
        note(.saved(fileName: (path as NSString).lastPathComponent))
    }

    static func unique(_ path: String) -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return path }
        let ns = path as NSString
        let dir = ns.deletingLastPathComponent
        let stem = (ns.lastPathComponent as NSString).deletingPathExtension
        let ext = ns.pathExtension
        for i in 2..<1000 {
            let p = (dir as NSString).appendingPathComponent("\(stem) \(i).\(ext)")
            if !fm.fileExists(atPath: p) { return p }
        }
        return path
    }

    // MARK: odds and ends

    private func note(_ entry: RescueTrailEntry) {
        trail.append(entry)
        Diag.info("rescue: \(entry)")
    }

    static func contains(_ list: [AlsPluginSlot], _ s: AlsPluginSlot) -> Bool {
        list.contains { $0.uid.caseInsensitiveCompare(s.uid) == .orderedSame }
    }
}
