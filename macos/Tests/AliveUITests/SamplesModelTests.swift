import XCTest
@testable import AliveCore
@testable import AliveUI

/// A sample library made of silent files. Nothing here makes a sound: the WAVs are all zeros and the
/// player's volume is 0 whenever a test lets it play.
@MainActor
final class SamplesModelTests: XCTestCase {
    private var root = ""

    private func wav(_ frames: Int, seed: UInt8 = 0) -> Data {
        func le(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        let bytes = frames * 2
        var d = Array("RIFF".utf8) + le(36 + bytes, 4) + Array("WAVE".utf8) + Array("fmt ".utf8) + le(16, 4)
        d += le(1, 2) + le(1, 2) + le(44100, 4) + le(88200, 4) + le(2, 2) + le(16, 2)
        d += Array("data".utf8) + le(bytes, 4) + [UInt8](repeating: seed, count: bytes)
        return Data(d)
    }

    private func put(_ data: Data, _ rel: String) {
        let p = root + "/" + rel
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try! data.write(to: URL(fileURLWithPath: p))
    }

    /// An app model on a scratch data folder with one sample folder set.
    private func makeApp() throws -> AppModel {
        let base = NSTemporaryDirectory() + "alive-samples-ui-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: base + "/data", withIntermediateDirectories: true)
        root = base + "/Lib"
        put(wav(4410), "Drums/kick.wav")
        put(wav(4410), "Drums/Deep/copy.wav")
        put(wav(4410), "Pads/kick.wav")                       // the kick again: same name, size and content
        put(wav(8820, seed: 1), "Pads/warm.wav")
        addTeardownBlock { try? FileManager.default.removeItem(atPath: base) }
        let app = AppModel(dataDir: base + "/data")
        app.audio.volume = 0
        app.mutateSettings { $0.sampleRoots = [self.root] }
        return app
    }

    private func started(_ app: AppModel) async -> SamplesModel {
        let m = app.samples
        m.start()
        await m.loadTask?.value
        await m.scanTask?.value
        await m.settle()
        return m
    }

    private func rowID(_ m: SamplesModel, _ name: String) -> String? {
        m.listing.rows.first { rowName(m, $0) == name }?.id
    }

    private func rowName(_ m: SamplesModel, _ r: SampleRow) -> String {
        switch r.kind {
        case .folder(let f): return m.index.folders[f].name
        case .file(let f): return m.index.files[f].name
        }
    }

    func testStartWalksTheFoldersAndWritesTheCache() async throws {
        let app = try makeApp()
        let m = await started(app)
        XCTAssertTrue(m.isLoaded)
        XCTAssertFalse(m.isScanning)
        XCTAssertEqual(m.index.totalSamples, 4)
        XCTAssertEqual(m.shownCount, 4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.dataDir + "/samples.cache"))

        // A second model starts from the cache alone (no walk needed to show the tree).
        let again = AppModel(dataDir: app.dataDir)
        again.mutateSettings { $0.sampleRoots = [self.root] }
        again.samples.start()
        await again.samples.loadTask?.value
        XCTAssertEqual(again.samples.index.totalSamples, 4)
        await again.samples.scanTask?.value
    }

    func testLensesAndSearchChangeWhatIsShown() async throws {
        let app = try makeApp()
        let m = await started(app)
        XCTAssertEqual(m.listing.rows.count, 1, "the tree starts closed: the root only")
        XCTAssertFalse(m.isFlat)

        app.searchText = "kick"
        await m.settle()
        XCTAssertTrue(m.isFlat)
        XCTAssertEqual(m.shownCount, 2)
        app.searchText = ""

        m.lens = .duplicates
        await m.settle()
        XCTAssertEqual(m.shownCount, 2, "the two kicks")
        XCTAssertEqual(m.copies.copies(of: m.copies.files[0]), 1)

        m.lens = .neverUsed        // no sets at all: the whole root, once
        await m.settle()
        XCTAssertEqual(m.listing.rows.count, 1)
        XCTAssertTrue(m.usageUnknown, "the catalog has not been read: usage says \"…\"")

        m.lens = .mostUsed
        await m.settle()
        XCTAssertEqual(m.shownCount, 0)
    }

    func testShowFolderOpensTheTreeAndSelectsIt() async throws {
        let app = try makeApp()
        let m = await started(app)
        app.searchText = "zzz"
        app.tab = .home
        m.showFolder(root + "/Drums/Deep")
        await m.settle()
        XCTAssertEqual(app.tab, .samples)
        XCTAssertEqual(app.searchText, "")
        XCTAssertEqual(m.selection, SampleIndex.norm(root + "/Drums/Deep"))
        XCTAssertNil(m.outsideFolder)
        XCTAssertNotNil(rowID(m, "Deep"), "its parents are open, so the row is there")
        XCTAssertNotNil(rowID(m, "Drums"))
        XCTAssertNotNil(rowID(m, "kick.wav"), "and the open folder shows its own samples")
        XCTAssertEqual(m.scrollTarget?.id, m.selection, "the scroll waits for the rows it points at")
        XCTAssertNotNil(m.selectedKind)
    }

    func testShowFolderOutsideTheLibraryIsShownGracefully() async throws {
        let app = try makeApp()
        let m = await started(app)
        m.select(SampleIndex.norm(root + "/Drums"))
        m.showFolder("/Volumes/Elsewhere/Loops")
        XCTAssertEqual(m.outsideFolder, "/Volumes/Elsewhere/Loops")
        XCTAssertNil(m.selection)
        XCTAssertNil(m.selectedKind)
        // A later selection clears the notice.
        m.select(SampleIndex.norm(root + "/Pads"))
        XCTAssertNil(m.outsideFolder)
    }

    func testShowFolderBeforeTheCacheIsLoadedIsRemembered() async throws {
        let app = try makeApp()
        let m = app.samples
        m.showFolder(root + "/Pads")
        XCTAssertEqual(app.tab, .samples)
        XCTAssertNil(m.selection)
        await m.loadTask?.value
        await m.scanTask?.value
        XCTAssertEqual(m.selection, SampleIndex.norm(root + "/Pads"))
    }

    func testRemovingOrDisablingTheFolderEmptiesTheTreeAtOnce() async throws {
        let app = try makeApp()
        let m = await started(app)
        m.select(SampleIndex.norm(root))
        app.mutateSettings { $0.disabledSampleRoots = [self.root] }
        m.syncRoots()
        XCTAssertEqual(m.index.totalSamples, 0)
        XCTAssertNil(m.selection, "a selection whose row is gone is dropped")
        XCTAssertFalse(m.hasEnabledRoots)
        app.mutateSettings { $0.disabledSampleRoots = [] }
        m.syncRoots()
        await m.scanTask?.value
        XCTAssertEqual(m.index.totalSamples, 4)
    }

    func testAddFoldersTakesAFileAsItsFolderAndSaysWhenItIsKnown() async throws {
        let app = try makeApp()
        let m = await started(app)
        let other = (root as NSString).deletingLastPathComponent + "/More"
        put(wav(100), "../More/loop.wav")
        m.addFolders([other + "/loop.wav"])
        XCTAssertEqual(app.settings.sampleRoots, [root, other])
        XCTAssertEqual(app.toasts.last?.text, CommonStrings.rootAdded.f("More"))
        await m.scanTask?.value
        XCTAssertEqual(m.index.totalSamples, 5)

        m.addFolders([other])
        XCTAssertEqual(app.toasts.last?.text, SamplesStrings.alreadyInLibrary.s)
        m.addFolders(["/definitely/not/here"])
        XCTAssertEqual(app.settings.sampleRoots.count, 2)
    }

    func testColumnsAndSortPersistThroughSettings() async throws {
        let app = try makeApp()
        let m = await started(app)
        XCTAssertEqual(m.columnSpec.order, SampleColumn.defaults)
        m.toggleColumn(.modified)
        XCTAssertTrue(app.settings.sampleColumns.contains("Modified"))
        XCTAssertTrue(m.columnSpec.order.contains(.modified))
        m.toggleColumn(.modified)
        XCTAssertFalse(m.columnSpec.order.contains(.modified))

        m.sortBy(.size)
        XCTAssertEqual(m.sort, SampleSort(column: .size, descending: false))
        m.sortBy(.size)
        XCTAssertEqual(m.sort, SampleSort(column: .size, descending: true))
        m.lens = .duplicates
        XCTAssertNil(m.sort.column, "every lens has an order of its own")
        XCTAssertTrue(m.visibleColumns.contains(.copies))
    }

    func testTreeKeysOpenCloseAndStepToTheParent() async throws {
        let app = try makeApp()
        let m = await started(app)
        let rootID = SampleIndex.norm(root)
        m.select(rootID)
        XCTAssertTrue(m.treeKey(open: true))
        XCTAssertTrue(m.isOpen(rootID))
        await m.settle()
        XCTAssertEqual(m.listing.rows.count, 3, "root, Drums, Pads")
        m.select(m.listing.rows[1].id)
        XCTAssertTrue(m.treeKey(open: true))
        XCTAssertTrue(m.treeKey(open: false))
        XCTAssertTrue(m.treeKey(open: false), "closed folder: step to the parent")
        XCTAssertEqual(m.selection, rootID)
        m.toggleFolder(rootID)
        await m.settle()
        XCTAssertEqual(m.listing.rows.count, 1)

        app.searchText = "a"
        XCTAssertFalse(m.treeKey(open: true), "a flat list has no levels")
    }

    func testArrowsWalkTheRowsAndAFolderNeverPlays() async throws {
        let app = try makeApp()
        let m = await started(app)
        m.toggleFolder(SampleIndex.norm(root))
        await m.settle()
        m.moveSelection(by: 1)
        XCTAssertEqual(m.selection, m.listing.rows[0].id)
        m.moveSelection(by: 1)
        m.moveSelection(by: 1)
        m.moveSelection(by: 1)
        XCTAssertEqual(m.selection, m.listing.rows[2].id, "stops at the last row")
        XCTAssertNil(app.audio.url)
        m.moveSelection(by: -5)
        XCTAssertEqual(m.selection, m.listing.rows[0].id)
    }

    func testAuditionGoesThroughTheSharedPlayerAndStopsWithTheTab() async throws {
        let app = try makeApp()
        let m = await started(app)
        m.lens = .duplicates
        await m.settle()
        let row = try XCTUnwrap(m.listing.rows.first)
        guard case .file(let f) = row.kind else { return XCTFail("a sample row") }
        let path = m.index.path(of: f)

        m.click(row)
        try XCTSkipIf(app.audio.url == nil, "no audio output on this machine")
        XCTAssertEqual(app.audio.url?.path, path)
        XCTAssertEqual(app.audio.volume, 0)
        XCTAssertEqual(m.selection, path)

        m.togglePlaySelected()                    // Space: the playing one stops
        XCTAssertNil(app.audio.url)
        m.togglePlaySelected()                    // and starts again
        XCTAssertEqual(app.audio.url?.path, path)
        m.leave()
        XCTAssertNil(app.audio.url, "leaving the tab silences the preview")
        XCTAssertNil(m.auditioned)
    }

    func testLeavingDoesNotStopWhatTheRenderPlayerIsPlaying() async throws {
        let app = try makeApp()
        let m = await started(app)
        let render = URL(fileURLWithPath: root + "/Pads/warm.wav")
        guard app.audio.play(url: render) else { throw XCTSkip("no audio output on this machine") }
        m.leave()
        XCTAssertEqual(app.audio.url, render)
        app.audio.stop()
    }

    func testAFilePreviewCannotPlayStaysSilentAndFolderClicksStopNothingElse() async throws {
        let app = try makeApp()
        put(Data("rex".utf8), "Pads/loop.rx2")
        let m = await started(app)
        let path = SampleIndex.norm(root + "/Pads/loop.rx2")
        m.select(path)
        m.togglePlaySelected()
        XCTAssertNil(app.audio.url)
        XCTAssertNil(m.dragURL(for: SampleRow(id: SampleIndex.norm(root), kind: .folder(0), depth: 0)), "folders do not drag")
        if case .file(let f)? = m.kind(ofRow: path) {
            XCTAssertNotNil(m.dragURL(for: SampleRow(id: path, kind: .file(f), depth: 0)))
        } else {
            XCTFail("the rx2 is a sample")
        }
    }

    func testAMissingFileToastsInsteadOfPlaying() async throws {
        let app = try makeApp()
        let m = await started(app)
        let path = SampleIndex.norm(root + "/Pads/warm.wav")
        m.select(path)
        try FileManager.default.removeItem(atPath: path)
        m.togglePlaySelected()
        XCTAssertNil(app.audio.url)
        XCTAssertEqual(app.toasts.last?.text, CommonStrings.pathMissing.f(path))
    }

    func testRescanRestartsAWalkUnderWay() async throws {
        let app = try makeApp()
        let m = await started(app)
        put(wav(50), "Pads/new.wav")
        m.rescan()
        XCTAssertTrue(m.isScanning)
        XCTAssertTrue(m.isManualScan)
        m.rescan()                                 // called off and started again
        await m.scanTask?.value
        for _ in 0..<50 where m.isScanning { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(m.index.totalSamples, 5)
    }

    func testInfoIsReadForTheSelectedSample() async throws {
        let app = try makeApp()
        let m = await started(app)
        let path = SampleIndex.norm(root + "/Pads/warm.wav")
        m.select(path)
        await m.infoTask?.value
        XCTAssertEqual(m.info?.path, path)
        XCTAssertEqual(m.info?.durationMs, 200)
        XCTAssertFalse(m.info?.format.isEmpty ?? true)
        m.select(SampleIndex.norm(root))
        XCTAssertNil(m.info)
    }
}
