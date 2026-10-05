// Mac-only: Samples tab state (upstream: the Samples half of MainForm, src/SamplesTab.cs). Owns the
// library index, what the sets use of it, the lens, sort, open folders and selection. Scanning is
// in SamplesModel+Scan, audition in SamplesModel+Audition. Nothing here plays sound on its own.
import Foundation
import Observation
import AliveCore

/// Asks the list to scroll a row into view; `serial` makes a repeated request for the same row count.
struct SampleScrollTarget: Equatable {
    let id: String
    let serial: Int
}

@MainActor
@Observable
final class SamplesModel {
    @ObservationIgnored unowned let app: AppModel

    // MARK: the library
    /// The library as last walked (or read from `samples.cache`).
    var index = SampleIndex.empty
    /// Bumped whenever `index` is replaced; lets the memos below know.
    var indexGeneration = 0
    /// `samples.cache` has been read (or there was none).
    var isLoaded = false
    var isScanning = false
    /// A rescan the person asked for shows its progress; the quiet one at launch does not.
    var isManualScan = false
    var found = 0
    /// What the previous walk found: the progress bar's 100 %.
    var estimate = 0

    // MARK: the view
    var lens = SampleLens.all {
        didSet { if lens != oldValue { sort = SampleSort() } }        // every lens has an order of its own
    }
    var sort = SampleSort()
    var openFolders = Set<String>()
    var openRevision = 0
    /// The view asks for the roots to be shown open the first time a library arrives, so the packs are in
    /// sight at once; the model itself starts with everything closed.
    @ObservationIgnored var expandsRootsOnFirstLoad = false
    var selection: String?
    private(set) var scrollTarget: SampleScrollTarget?
    /// A folder that `showFolder` was asked for but that is not in the library.
    var outsideFolder: String?
    var info: SampleInfo?

    // MARK: audition
    /// The sample the selection last played, so a refill that puts the same row back does not play it again.
    var auditioned: String?
    @ObservationIgnored var startedPath: String?
    @ObservationIgnored var lastStart = Date.distantPast

    // MARK: scanning
    @ObservationIgnored var started = false
    @ObservationIgnored var scannedKey: String?
    @ObservationIgnored var restartRequested = false
    @ObservationIgnored var scanFlag: SampleCancelFlag?
    @ObservationIgnored var scanTask: Task<Void, Never>?
    @ObservationIgnored var loadTask: Task<Void, Never>?
    @ObservationIgnored var pendingReveal: String?
    @ObservationIgnored var scrollSerial = 0
    @ObservationIgnored var infoTask: Task<Void, Never>?

    // MARK: derived data (see SamplesSnapshot)
    /// The last finished build. Published once per build; the getters below read it.
    private(set) var snapshot: SamplesSnapshot?
    /// Per-folder summaries for the panel, valid for one (index, catalog revision).
    @ObservationIgnored private var folderSummaries: [Int: SampleFolderSummary] = [:]
    /// Bumped when a summary arrives, so the panel reads again.
    private(set) var summaryRevision = 0
    @ObservationIgnored private var summaryStamp = ""
    @ObservationIgnored private var summaryTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var building: SamplesSnapshotKey?
    @ObservationIgnored private var buildSerial = 0
    /// Index generation for which a panel has asked for the copies.
    @ObservationIgnored private var copiesDemandedGeneration = -1
    /// A scroll asked for before the rows it points at have been built; done when they arrive.
    @ObservationIgnored private var deferredScroll: String?
    @ObservationIgnored private var lookupGeneration = -1
    @ObservationIgnored private var folderLookup: [String: Int] = [:]
    @ObservationIgnored private var folderGroups: [String: [Int]] = [:]
    @ObservationIgnored private var fileLookups: [Int: [String: Int]] = [:]

    init(app: AppModel) {
        self.app = app
    }

    // MARK: - Toolbar contract

    /// The toolbar's "N shown": the whole library in the tree, the rows in a list.
    var shownCount: Int {
        isFlat ? listing.rows.count : index.totalSamples
    }

    /// The toolbar's counter text: "12,923 samples · 23.7 GB" for the tree, or what the list shows.
    var shownLabel: String {
        SampleCounter.text(isScanning: isScanning && isManualScan, found: found, listing: listing, lens: lens,
                           hasQuery: !app.searchText.isEmpty, index: index, copies: copies)
    }

    /// The app-wide player (`app.audio`), shared with render playback.
    var audio: AudioPlayback { app.audio }

    /// Reads the library again (⌘R on this tab). A walk under way is called off and started anew.
    func rescan() {
        guard started else { start(); return }        // the first start walks by itself
        guard hasEnabledRoots else { return }
        scannedKey = effectiveRoots.joined(separator: "\n")
        startScan(manual: true)
    }

    /// Opens the Samples tab on a library folder (from a set's "sample folders" in the Sets
    /// inspector). Cross-feature entry point: keep this signature. The folder may be outside the
    /// library: the panel then says so, and offers to add it.
    func showFolder(_ path: String) {
        app.tab = .samples
        start()
        guard isLoaded else { pendingReveal = path; return }
        reveal(path)
    }

    // MARK: - Derived data

    var isFlat: Bool { SampleLister.isFlat(lens: lens, query: app.searchText) }

    /// The usage columns say "…" rather than "never" while the sets have not been read yet: right
    /// after an update the whole catalog is parsed anew, and for that half a minute everything
    /// would look unused.
    var usageUnknown: Bool {
        (app.catalog.sets.isEmpty && (app.catalog.isScanning || !app.catalog.isLoaded))
            || snapshot?.key.indexGeneration != indexGeneration
    }

    /// What the sets use of the library. Empty until the snapshot for the current index has been
    /// published (`usageUnknown` says so); between two catalog revisions the previous one stays.
    var usage: SampleUsage { readSnapshot()?.usage ?? .empty }

    /// The same sample in several places. Only there when something shows it: the Duplicates lens,
    /// a Copies column or a sort by it, or the panel (`copiesForPanel`).
    var copies: SampleCopies { readSnapshot()?.copies ?? .empty }

    /// The copies for the panel of a folder or sample: asks for them to be found when they are not.
    var copiesForPanel: SampleCopies {
        if copiesDemandedGeneration != indexGeneration {
            copiesDemandedGeneration = indexGeneration
            scheduleSnapshot()
        }
        return copies
    }

    /// The rows of the list for the lens, order, open folders and the search box; the previous
    /// ones (of the same library) while the new ones are being built.
    var listing: SampleListing { readSnapshot()?.listing ?? Self.emptyListing }

    private static let emptyListing = SampleLister.listing(index: .empty, usage: .empty, copies: .empty, lens: .all,
                                                           sort: SampleSort(), open: [], query: "")

    /// The rows for the current inputs have not been published yet.
    var isPreparing: Bool { snapshot?.key != snapshotKey }

    /// Waits until the snapshot matches the current inputs. For tests and for callers that must act
    /// on the finished rows.
    func settle() async {
        scheduleSnapshot()
        while let task = snapshotTask {
            await task.value
            scheduleSnapshot()
        }
    }

    private var snapshotKey: SamplesSnapshotKey {
        let wantsCopies = lens == .duplicates || sort.column == .copies || visibleColumns.contains(.copies)
            || copiesDemandedGeneration == indexGeneration
        return SamplesSnapshotKey(indexGeneration: indexGeneration, catalogRevision: app.catalog.revision, lens: lens,
                                  sort: sort, openRevision: openRevision, query: app.searchText, wantsCopies: wantsCopies)
    }

    /// The published snapshot when it belongs to the current library (its row numbers point into
    /// `index`); a build is started when the inputs have moved on.
    private func readSnapshot() -> SamplesSnapshot? {
        scheduleSnapshot()
        guard let s = snapshot, s.key.indexGeneration == indexGeneration else { return nil }
        return s
    }

    private func scheduleSnapshot() {
        let key = snapshotKey
        if snapshot?.key == key || building == key { return }
        snapshotTask?.cancel()
        buildSerial += 1
        let serial = buildSerial
        building = key
        let input = SamplesSnapshotInput(key: key, index: index, sets: app.catalog.sets, open: openFolders,
                                         previous: snapshot)
        snapshotTask = Task { [weak self] in
            let built = await BlockingWork.run { isCancelled in
                SamplesSnapshotBuilder.build(input, isCancelled: isCancelled)
            }
            self?.publish(built, serial: serial)
        }
    }

    private func publish(_ built: SamplesSnapshot?, serial: Int) {
        guard serial == buildSerial else { return }              // a newer request has taken over
        building = nil
        snapshotTask = nil
        guard let built else { return }
        snapshot = built
        if let id = deferredScroll, built.key == snapshotKey {
            deferredScroll = nil
            publishScroll(to: id)
        }
    }

    // MARK: - Folder panel

    /// What the folder panel needs beyond the snapshot, or nil while it is being worked out.
    func folderSummary(_ folder: Int) -> SampleFolderSummary? {
        _ = summaryRevision
        guard let usage = readSnapshot()?.usage, !usageUnknown else { return nil }
        let stamp = "\(indexGeneration)|\(app.catalog.revision)"
        if stamp != summaryStamp {
            summaryStamp = stamp
            summaryTasks.values.forEach { $0.cancel() }
            summaryTasks = [:]
            folderSummaries = [:]
        }
        if let ready = folderSummaries[folder] { return ready }
        guard summaryTasks[folder] == nil else { return nil }
        let index = self.index
        summaryTasks[folder] = Task { [weak self] in
            let made = await BlockingWork.run { isCancelled in
                isCancelled() ? nil : SampleFolderSummary.make(folder: folder, index: index, usage: usage)
            }
            guard let self, let made, self.summaryStamp == stamp else { return }
            self.summaryTasks[folder] = nil
            if self.folderSummaries.count >= Self.summaryCapacity { self.folderSummaries = [:] }
            self.folderSummaries[folder] = made
            self.summaryRevision &+= 1
        }
        return nil
    }

    private static let summaryCapacity = 24

    var columnSpec: SampleColumnSpec { SampleColumnSpec(spec: app.settings.sampleColumns) }

    var visibleColumns: [SampleColumn] { columnSpec.visible(lens: lens, isFlat: isFlat) }

    func toggleColumn(_ column: SampleColumn) {
        let next = columnSpec.toggling(column).spec
        app.mutateSettings { $0.sampleColumns = next }
    }

    // MARK: - Lookups

    private func prepareFolderLookup() {
        guard lookupGeneration != indexGeneration else { return }
        folderLookup = index.folderLookup()
        folderGroups = Dictionary(grouping: index.folders.indices) { index.folders[$0].path.lowercased() }
        fileLookups = [:]
        lookupGeneration = indexGeneration
    }

    func kind(ofRow id: String?) -> SampleRow.Kind? {
        guard let id else { return nil }
        let key = id.lowercased()
        prepareFolderLookup()
        if let f = folderLookup[key] { return .folder(f) }
        let parent = (key as NSString).deletingLastPathComponent
        guard let folder = folderLookup[parent] else { return nil }
        // Opening one folder must not build full paths for every sample in the library.
        // File selection only needs names in its containing folder; retain a small working set.
        if fileLookups[folder] == nil {
            var names: [String: Int] = [:]
            names.reserveCapacity(index.folders[folder].files.count)
            // A case-sensitive volume can contain both Kicks/ and kicks/. Preserve the old
            // case-insensitive full-path lookup, including its last-file-index tie break.
            for samePath in folderGroups[parent] ?? [folder] {
                for f in index.folders[samePath].files {
                    let name = index.files[f].name.lowercased()
                    names[name] = max(names[name] ?? f, f)
                }
            }
            if fileLookups.count >= Self.summaryCapacity { fileLookups = [:] }
            fileLookups[folder] = names
        }
        if let f = fileLookups[folder]?[(key as NSString).lastPathComponent] { return .file(f) }
        return nil
    }

    var selectedKind: SampleRow.Kind? { kind(ofRow: selection) }

    // MARK: - Selection

    /// Programmatic selection: nothing is played.
    func select(_ id: String?) {
        guard selection != id else { return }
        selection = id
        outsideFolder = nil
        loadInfo()
    }

    private func loadInfo() {
        infoTask?.cancel()
        guard case .file(let f)? = selectedKind else { info = nil; return }
        let path = index.path(of: f), file = index.files[f]
        if info?.path == path { return }
        info = SampleInfo(path: path)
        infoTask = Task { [weak self] in
            // Cancelling the task (another sample selected) reaches the decoder through the flag.
            let loaded = await BlockingWork.run { isCancelled in
                SampleInfoLoader.load(path: path, canPreview: file.canPreview, size: file.size, buckets: 300,
                                      isCancelled: isCancelled)
            }
            guard let self, !Task.isCancelled, self.selection == path else { return }
            self.info = loaded
        }
    }

    func requestScroll(to id: String) {
        // The row may not be in the list yet: the list is built off the main actor.
        if isPreparing { deferredScroll = id; scheduleSnapshot(); return }
        publishScroll(to: id)
    }

    private func publishScroll(to id: String) {
        scrollSerial += 1
        scrollTarget = SampleScrollTarget(id: id, serial: scrollSerial)
    }

    // MARK: - Tree

    func isOpen(_ id: String) -> Bool { openFolders.contains(id.lowercased()) }

    func toggleFolder(_ id: String) {
        guard case .folder(let f)? = kind(ofRow: id), !isFlat else { return }
        let d = index.folders[f]
        guard d.children.count + d.files.count > 0 else { return }
        setOpen(id, !isOpen(id))
    }

    private func setOpen(_ id: String, _ open: Bool) {
        let key = id.lowercased()
        if open { openFolders.insert(key) } else { openFolders.remove(key) }
        openRevision += 1
    }

    /// Show something in the tree: the All lens, no search, every folder above it open, the row
    /// selected. From a flat list, from the panel's "Most used" and from a set's panel.
    func showInTree(_ id: String) {
        guard let kind = kind(ofRow: id) else { return }
        let container: Int
        switch kind {
        case .folder(let f): container = index.folders[f].parent ?? f
        case .file(let f): container = index.files[f].folder
        }
        lens = .all
        if !app.searchText.isEmpty { app.searchText = "" }
        openFolders.formUnion(SampleLister.ancestors(of: container, in: index))
        openRevision += 1
        select(id)
        requestScroll(to: id)
    }

    /// → opens the selected folder, ← closes it — or, on a closed folder or a sample, steps to the
    /// parent. Only in the tree: a flat list has no levels. Returns whether the key was used.
    func treeKey(open: Bool) -> Bool {
        guard !isFlat, let sel = selection, let kind = selectedKind else { return false }
        if case .folder(let f) = kind {
            let isOpen = isOpen(sel)
            if open {
                if !isOpen { toggleFolder(sel) }
                return true
            }
            if isOpen { toggleFolder(sel); return true }
            if let p = index.folders[f].parent { selectAndScroll(index.folders[p].path) }
            return true
        }
        if !open, case .file(let f) = kind { selectAndScroll(index.folders[index.files[f].folder].path) }
        return true
    }

    func selectAndScroll(_ id: String) {
        select(id)
        requestScroll(to: id)
    }

    // MARK: - Roots

    var effectiveRoots: [String] {
        SampleIndex.effective(app.settings.sampleRoots, disabled: app.settings.disabledSampleRoots)
    }

    var hasEnabledRoots: Bool { !effectiveRoots.isEmpty }

    /// Folders dropped on the window or chosen in a panel: a file counts as its folder.
    func addFolders(_ paths: [String]) {
        var added: [String] = []
        app.mutateSettings { s in
            for path in paths {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
                let folder = isDir.boolValue ? path : (path as NSString).deletingLastPathComponent
                if SampleIndex.containsPath(s.sampleRoots, folder) { continue }
                s.sampleRoots.append(folder)
                s.disabledSampleRoots.removeAll { SampleIndex.containsPath([$0], folder) }
                let name = (folder as NSString).lastPathComponent
                added.append(name.isEmpty ? folder : name)
            }
        }
        if added.isEmpty {
            app.toast(SamplesStrings.alreadyInLibrary.s)
            return
        }
        app.toast(added.count == 1 ? CommonStrings.rootAdded.f(added[0]) : CommonStrings.rootsAdded.f(added.count))
        syncRoots()
    }
}
