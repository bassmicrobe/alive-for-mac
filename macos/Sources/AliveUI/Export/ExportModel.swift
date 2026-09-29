// Mac-only: state of the Export sheet (upstream CollectDialog's logic). One sheet, two states —
// choosing and copying — for the same reason as Rescue: this is one act rather than two.
//
// The items are exactly the four "Collect All and Save" asks in Live. Over and above that, the
// file count and the weight are shown: 5.8 GB of packs has to be seen BEFORE Export is pressed.
// Nothing is created until then, and the original set is only ever read.
import AliveCore
import Foundation
import Observation

/// What went wrong, typed so the sheet localizes it (one inline message, never one per file).
enum ExportFailure: Equatable {
    case destinationExists(String)
    case notEnoughSpace(needed: Int64, free: Int64)
    case pack(String)
    case setNotWritten(String)
    case io(String)
    case cancelled

    init(_ error: Error) {
        switch error as? CollectError {
        case .destinationExists(let p)?: self = .destinationExists(p)
        case .notEnoughSpace(let n, let f)?: self = .notEnoughSpace(needed: n, free: f)
        case .packFailed(_, let out)?: self = .pack(out)
        case .setNotWritten(let s)?: self = .setNotWritten(s)
        case .io(let s)?: self = .io(s)
        case .cancelled?: self = .cancelled
        case nil: self = .io(error.localizedDescription)
        }
    }
}

@MainActor
@Observable
final class ExportModel {
    enum Phase: Equatable { case idle, counting, ready, running, done }

    @ObservationIgnored unowned let app: AppModel

    private(set) var phase: Phase = .idle
    private(set) var set = SetEntry()
    /// The set could not be read at all.
    private(set) var readError: String?
    private(set) var options = CollectOptions()
    private(set) var plan: CollectPlan?
    /// The folder that will be created (with ".zip" appended for an archive).
    private(set) var targetDir = ""
    private(set) var progress: CollectProgress?
    private(set) var failure: ExportFailure?
    private(set) var result: CollectResult?
    private(set) var cancelling = false
    /// The destination is taken already. Kept, not computed: it used to hit the disk on every
    /// render of the sheet; now it is refreshed when the plan changes.
    private(set) var destinationExists = false

    @ObservationIgnored private var info: AlsInfo?
    @ObservationIgnored private var deps: [CollectDependency] = []
    @ObservationIgnored private var runTask: Task<Result<CollectResult, Error>, Never>?
    @ObservationIgnored private var generation = 0

    init(app: AppModel) {
        self.app = app
    }

    // MARK: derived

    var groups: [CollectGroup] { plan?.groups ?? [] }
    var notFound: [CollectDependency] { plan?.notFound ?? [] }
    var fits: Bool { plan?.fits ?? false }
    var outputPath: String { plan?.outputPath ?? targetDir }

    var refused: [CollectDependency] { plan?.refused ?? [] }
    var elsewhereFolders: [String] { plan?.elsewhereFolders ?? [] }

    /// Nothing is ever merged into or replaced: whether the folder (or archive) exists is
    /// looked at when the plan is made, not on every render.
    private func refreshDestinationExists() {
        let fm = FileManager.default
        destinationExists = !targetDir.isEmpty
            && (fm.fileExists(atPath: targetDir) || (options.toZip && fm.fileExists(atPath: targetDir + ".zip")))
    }

    var canExport: Bool { phase == .ready && plan != nil && fits && !destinationExists }
    var canEditOptions: Bool { phase == .ready }

    // MARK: lifecycle

    /// Reads the set and counts the files off the main thread; toggles stay disabled until then.
    func open(path: String) async {
        close()
        generation += 1
        let mine = generation
        phase = .counting
        var entry = app.catalog.sets.first { $0.path == path } ?? SetEntry()
        if entry.path.isEmpty {
            entry.path = path
            entry.name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        set = entry
        options = CollectOptions(settings: app.settings)
        targetDir = CollectAll.freeTarget(for: entry)

        let env = app.catalog.env
        let (read, found): (AlsInfo, [CollectDependency]) = await BlockingWork.run { isCancelled in
            let info = AlsFile.read(path: path)
            guard info.error == nil else { return (info, []) }
            return (info, CollectScan.of(info, setDir: (path as NSString).deletingLastPathComponent, env: env,
                                         isCancelled: isCancelled))
        }
        guard mine == generation else { return }

        info = read
        deps = found
        if let e = read.error {
            readError = e
        } else {
            replan()
        }
        phase = .ready
    }

    /// Closing while a copy runs stops it (and whatever it created is removed).
    func close() {
        generation += 1
        runTask?.cancel()
        runTask = nil
        phase = .idle
        plan = nil
        info = nil
        deps = []
        readError = nil
        progress = nil
        failure = nil
        result = nil
        cancelling = false
        destinationExists = false
    }

    // MARK: choices

    func setIncluded(_ origin: CollectOrigin, _ on: Bool) {
        guard canEditOptions else { return }
        switch origin {
        case .elsewhere: options.fromElsewhere = on
        case .otherProject: options.fromOtherProjects = on
        case .userLibrary: options.fromUserLibrary = on
        case .factoryPack: options.fromFactoryPacks = on
        case .inProject, .missing: return
        }
        replan()
    }

    func setZip(_ on: Bool) {
        guard canEditOptions else { return }
        options.toZip = on
        failure = nil
        replan()
    }

    /// The person picked another place/name in the save panel; `path` is the folder to create
    /// (a trailing ".zip" is the archive name typed in zip mode and is dropped).
    func setDestination(_ path: String) {
        guard canEditOptions else { return }
        targetDir = Self.stripZip(path)
        failure = nil
        replan()
    }

    nonisolated static func stripZip(_ path: String) -> String {
        path.lowercased().hasSuffix(".zip") ? String(path.dropLast(4)) : path
    }

    /// Where the save panel starts, and what it proposes as the name.
    var suggestedName: String { (targetDir as NSString).lastPathComponent + (options.toZip ? ".zip" : "") }
    var suggestedFolder: String { (targetDir as NSString).deletingLastPathComponent }

    private func replan() {
        plan = CollectAll.plan(set: set, deps: deps, options: options, targetDir: targetDir)
        refreshDestinationExists()
    }

    // MARK: exporting

    func start() async {
        guard canExport, let plan, let info else { return }
        app.mutateSettings { options.store(in: &$0) }

        phase = .running
        failure = nil
        cancelling = false
        progress = CollectProgress(phase: .copying, done: 0, total: plan.copy.count, current: "")
        let entry = set
        let mine = generation
        // On a queue of its own (copying gigabytes must not hold the cooperative pool);
        // cancelling this task is what stops the copy.
        let task = Task { [weak self] () -> Result<CollectResult, Error> in
            do {
                return .success(try await BlockingWork.run { isCancelled in
                    try CollectAll.run(plan: plan, set: entry, info: info,
                                       progress: { p in Task { @MainActor in self?.report(p, generation: mine) } },
                                       isCancelled: isCancelled)
                })
            } catch { return .failure(error) }
        }
        runTask = task
        let outcome = await task.value
        guard mine == generation else { return }
        runTask = nil

        switch outcome {
        case .success(let r):
            result = r
            phase = .done
            app.toast(ExportStrings.toastDone.f((r.output as NSString).lastPathComponent))
        case .failure(let error):
            let f = ExportFailure(error)
            if f != .cancelled { Diag.fail("export", error) }
            failure = f
            phase = .ready
            replan()                                    // free space may have changed during the attempt
        }
        progress = nil
        cancelling = false
    }

    private func report(_ p: CollectProgress, generation g: Int) {
        guard g == generation, phase == .running else { return }
        progress = p
    }

    func cancel() {
        guard phase == .running else { return }
        cancelling = true
        runTask?.cancel()
    }

    func revealResult() {
        guard let out = result?.output else { return }
        app.revealInFinder(path: out)
    }
}
