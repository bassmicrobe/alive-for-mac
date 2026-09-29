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

    // MARK: memos
    @ObservationIgnored private var usageMemo: (key: String, value: SampleUsage)?
    @ObservationIgnored private var copiesMemo: (gen: Int, value: SampleCopies)?
    @ObservationIgnored private var keysMemo: (gen: Int, value: SampleNameKeys)?
    @ObservationIgnored private var lookupMemo: (gen: Int, folders: [String: Int], files: [String: Int])?
    @ObservationIgnored private var listingMemo: (key: String, value: SampleListing)?

    init(app: AppModel) {
        self.app = app
    }

    // MARK: - Toolbar contract

    /// The toolbar's "N shown": the whole library in the tree, the rows in a list.
    var shownCount: Int {
        isFlat ? listing.rows.count : index.totalSamples
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
        app.catalog.sets.isEmpty && (app.catalog.isScanning || !app.catalog.isLoaded)
    }

    /// What the sets use of the library — worked out anew only when the sets or the index changed
    /// (74 ms on 184 thousand samples upstream).
    var usage: SampleUsage {
        let key = "\(indexGeneration)|\(app.catalog.revision)"
        if let m = usageMemo, m.key == key { return m.value }
        let value = SampleUsage.compute(index: index, sets: app.catalog.sets)
        usageMemo = (key, value)
        return value
    }

    /// The same sample in several places — found anew only for a new index.
    var copies: SampleCopies {
        if let m = copiesMemo, m.gen == indexGeneration { return m.value }
        let value = SampleCopies.find(in: index)
        copiesMemo = (indexGeneration, value)
        return value
    }

    private var nameKeys: SampleNameKeys {
        if let m = keysMemo, m.gen == indexGeneration { return m.value }
        let value = SampleNameKeys(index)
        keysMemo = (indexGeneration, value)
        return value
    }

    /// The rows of the list for the lens, order, open folders and the search box.
    var listing: SampleListing {
        let query = app.searchText
        let key = "\(indexGeneration)|\(app.catalog.revision)|\(lens.rawValue)|\(sort.column?.rawValue ?? "-")"
            + "\(sort.descending)|\(openRevision)|\(query)"
        if let m = listingMemo, m.key == key { return m.value }
        let value = SampleLister.listing(index: index, usage: usage, copies: copies, lens: lens, sort: sort,
                                         open: openFolders, query: query, keys: nameKeys)
        listingMemo = (key, value)
        return value
    }

    var columnSpec: SampleColumnSpec { SampleColumnSpec(spec: app.settings.sampleColumns) }

    var visibleColumns: [SampleColumn] { columnSpec.visible(lens: lens, isFlat: isFlat) }

    func toggleColumn(_ column: SampleColumn) {
        let next = columnSpec.toggling(column).spec
        app.mutateSettings { $0.sampleColumns = next }
    }

    // MARK: - Lookups

    private var lookups: (folders: [String: Int], files: [String: Int]) {
        if let m = lookupMemo, m.gen == indexGeneration { return (m.folders, m.files) }
        var files: [String: Int] = [:]
        files.reserveCapacity(index.files.count)
        for i in index.files.indices { files[index.path(of: i).lowercased()] = i }
        let folders = index.folderLookup()
        lookupMemo = (indexGeneration, folders, files)
        return (folders, files)
    }

    func kind(ofRow id: String?) -> SampleRow.Kind? {
        guard let id else { return nil }
        let key = id.lowercased()
        let l = lookups
        if let f = l.folders[key] { return .folder(f) }
        if let f = l.files[key] { return .file(f) }
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
            let loaded = await Task.detached(priority: .userInitiated) {
                SampleInfoLoader.load(path: path, canPreview: file.canPreview, size: file.size, buckets: 300)
            }.value
            guard let self, !Task.isCancelled, self.selection == path else { return }
            self.info = loaded
        }
    }

    func requestScroll(to id: String) {
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
