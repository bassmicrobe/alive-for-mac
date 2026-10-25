import XCTest
import AliveCore
@testable import AliveUI

@MainActor
final class RootsSubmissionTests: XCTestCase {
    private func model(_ scratch: HomeScratch, projects: [String], samples: [String] = [],
                       disabled: [String] = []) -> AppModel {
        scratch.write("data/settings.cfg", "spotlight=0\nmenubar=0\nfindertags=0\n")
        let app = AppModel(dataDir: scratch.sub("data"))
        app.catalog.index.inventoryLoader = { _ in PluginInventory() }
        app.mutateSettings {
            $0.roots = projects
            $0.disabledRoots = disabled
            $0.sampleRoots = samples
        }
        return app
    }

    private func draft(_ app: AppModel, kind: RootsKind) -> RootsDraft {
        RootsDraft(kind: kind, projects: .init(roots: app.settings.roots, disabled: app.settings.disabledRoots),
                   samples: .init(roots: app.settings.sampleRoots, disabled: app.settings.disabledSampleRoots))
    }

    private func startCatalog(_ app: AppModel) async throws {
        app.catalog.start()
        // These tests exercise explicit submission, independently of automatic FSEvents refresh.
        app.sets.watcher.stop()
        app.sets.watcher.waitUntilArmed()
        try await waitForCatalog(app)
    }

    private func waitForCatalog(_ app: AppModel) async throws {
        for _ in 0..<400 where !app.catalog.isReady {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(app.catalog.isReady)
    }

    func testUnchangedProjectSelectionReallyRescansAndDoesNotStartSamples() async throws {
        let scratch = makeHomeScratch()
        let path = try scratch.writeSet("lib/A Project/a.als")
        _ = try scratch.writeWav("samples/kick.wav")
        let root = scratch.sub("lib")
        let app = model(scratch, projects: [root], samples: [scratch.sub("samples")])
        try await startCatalog(app)
        let initial = try XCTUnwrap(app.catalog.sets.first)
        let xml = HomeFixtures.setXML(withClip: true).replacingOccurrences(of: "12.3.5", with: "12.3.6")
        try Gzip.compress(Data(xml.utf8)).write(to: URL(fileURLWithPath: path))
        scratch.setModified(path, initial.modified.addingTimeInterval(5))

        let draft = draft(app, kind: .projects)
        XCTAssertFalse(draft.page.add(root), "selecting the same folder does not edit the draft")
        XCTAssertFalse(draft.hasChanges)
        draft.apply(to: app)

        XCTAssertTrue(app.catalog.isScanning, "Scan must retry even when the selection is unchanged")
        XCTAssertFalse(app.samples.started, "only the selected page should scan")
        try await waitForCatalog(app)
        XCTAssertEqual(app.catalog.sets.first?.shortVersion, "12.3.6")
    }

    func testUnchangedSampleSelectionScansSamplesOnlyWithoutSavingSettings() async throws {
        let scratch = makeHomeScratch()
        _ = try scratch.writeSet("lib/A Project/a.als")
        _ = try scratch.writeWav("samples/kick.wav")
        let app = model(scratch, projects: [scratch.sub("lib")], samples: [scratch.sub("samples")])
        try await startCatalog(app)
        app.samples.start()
        await app.samples.loadTask?.value
        await app.samples.scanTask?.value
        let revision = app.catalog.revision
        let settingsPath = scratch.sub("data/settings.cfg")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)],
                                             ofItemAtPath: settingsPath)
        let saved = try XCTUnwrap(FileStat.of(settingsPath))
        _ = try scratch.writeWav("samples/snare.wav")

        draft(app, kind: .samples).apply(to: app)

        XCTAssertTrue(app.samples.isScanning)
        XCTAssertFalse(app.samples.restartRequested)
        XCTAssertFalse(app.catalog.isScanning)
        XCTAssertEqual(FileStat.of(settingsPath), saved, "an unchanged submission must not rewrite settings")
        await app.samples.scanTask?.value
        XCTAssertEqual(app.samples.index.totalSamples, 2)
        XCTAssertEqual(app.catalog.revision, revision)
    }

    func testEditingBothPagesStartsOneSampleWalkWithoutCancelingIt() async throws {
        let scratch = makeHomeScratch()
        _ = try scratch.writeSet("lib/A Project/a.als")
        _ = try scratch.writeSet("more/B Project/b.als")
        _ = try scratch.writeWav("samples/kick.wav")
        _ = try scratch.writeWav("more-samples/snare.wav")
        let app = model(scratch, projects: [scratch.sub("lib")], samples: [scratch.sub("samples")])
        try await startCatalog(app)
        app.samples.start()
        await app.samples.loadTask?.value
        await app.samples.scanTask?.value
        let draft = draft(app, kind: .samples)
        draft.projects.add(scratch.sub("more"))
        draft.samples.add(scratch.sub("more-samples"))

        draft.apply(to: app)

        XCTAssertTrue(app.catalog.isScanning)
        XCTAssertTrue(app.samples.isScanning)
        XCTAssertFalse(app.samples.restartRequested, "the settings hook already starts the sample walk")
        XCTAssertFalse(try XCTUnwrap(app.samples.scanFlag).isCancelled,
                       "submitting must not cancel the walk it just started")
        let saved = AppSettings.load(dir: app.dataDir)
        XCTAssertEqual(saved.roots, draft.projects.roots)
        XCTAssertEqual(saved.sampleRoots, draft.samples.roots)
        await app.samples.scanTask?.value
        try await waitForCatalog(app)
        XCTAssertEqual(app.catalog.sets.count, 2)
        XCTAssertEqual(app.samples.index.totalSamples, 2)
    }

    func testSubmissionCancelsOutstandingFolderCounts() async throws {
        let scratch = makeHomeScratch()
        let missing = scratch.sub("missing")
        let app = model(scratch, projects: [missing])
        let submitted = draft(app, kind: .projects)
        let control = draft(app, kind: .projects)
        submitted.ensureCount(missing)
        control.ensureCount(missing)
        submitted.apply(to: app)

        for _ in 0..<200 where control.count(for: missing) == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(control.count(for: missing), -1)
        XCTAssertNil(submitted.count(for: missing), "closed-sheet counts must not publish after Scan")
        control.cancelCounting()
    }

    func testSelectingADisabledExistingRootReenablesPersistsAndScansIt() async throws {
        let scratch = makeHomeScratch()
        let path = try scratch.writeSet("lib/A Project/a.als")
        let root = scratch.sub("lib")
        let app = model(scratch, projects: [root], disabled: [root])
        try await startCatalog(app)
        XCTAssertFalse(app.catalog.hasEnabledRoots)

        XCTAssertEqual(app.catalog.addRoots([root + "/.", root]), [root])

        XCTAssertEqual(app.settings.roots, [root], "recovery must not duplicate the registered root")
        XCTAssertTrue(app.settings.disabledRoots.isEmpty)
        XCTAssertTrue(AppSettings.load(dir: app.dataDir).disabledRoots.isEmpty)
        XCTAssertTrue(app.catalog.isScanning)
        try await waitForCatalog(app)
        XCTAssertEqual(app.catalog.sets.map(\.path), [path])
        XCTAssertTrue(app.catalog.addRoots([root]).isEmpty, "an enabled duplicate still stays unchanged")
    }
}
