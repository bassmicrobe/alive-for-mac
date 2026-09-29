import AliveCore
import XCTest
@testable import AliveUI

final class ExportTextTests: XCTestCase {
    private var saved: LanguagePreference = .system

    override func setUp() {
        super.setUp()
        saved = Localizer.shared.preference
        Localizer.shared.preference = .en
    }

    override func tearDown() {
        Localizer.shared.preference = saved
        super.tearDown()
    }

    func testNumbersAndPlurals() {
        var g = CollectGroup(origin: .elsewhere)
        XCTAssertEqual(ExportText.groupNumbers(g), "—")
        g.files = 1
        g.bytes = 2_000_000
        XCTAssertTrue(ExportText.groupNumbers(g).hasPrefix("1 file    "))
        g.files = 28
        XCTAssertTrue(ExportText.groupNumbers(g).hasPrefix("28 files    "))
        XCTAssertEqual(ExportStrings.files(0), "0 files")
    }

    func testManyMissingFilesAreOneLine() {
        XCTAssertNil(ExportText.notFoundSummary(0))
        XCTAssertEqual(ExportText.notFoundSummary(1), "1 file not found — left as they are")
        XCTAssertEqual(ExportText.notFoundSummary(240), "240 files not found — left as they are")
        XCTAssertEqual(ExportText.failedSummary(3), "3 files could not be copied — their references were left as they were")
        XCTAssertNil(ExportText.failedSummary(0))
    }

    func testSummaryPriority() {
        var plan = CollectPlan()
        plan.copy = [CollectDependency(resolved: ResolvedRef(ref: FileRefInfo()))]
        plan.totalBytes = 1_000
        plan.freeBytes = 10_000
        var s = ExportText.summary(plan: plan, failure: nil, destinationExists: false, targetDir: "/a/X", outputPath: "/a/X")
        XCTAssertTrue(s.text.hasPrefix("Will copy 1 file, "))
        XCTAssertFalse(s.isError)

        plan.freeBytes = 10
        s = ExportText.summary(plan: plan, failure: nil, destinationExists: false, targetDir: "/a/X", outputPath: "/a/X")
        XCTAssertEqual(s.text, "Not enough space")
        XCTAssertTrue(s.isError)

        s = ExportText.summary(plan: plan, failure: nil, destinationExists: true, targetDir: "/a/X", outputPath: "/a/X.zip")
        XCTAssertTrue(s.text.contains("“X.zip” already exists"))

        s = ExportText.summary(plan: plan, failure: .io("disk\nline two"), destinationExists: false, targetDir: "", outputPath: "")
        XCTAssertEqual(s.text, "Could not export: disk", "one line on the shelf")
        XCTAssertTrue(s.isError)

        s = ExportText.summary(plan: plan, failure: .cancelled, destinationExists: false, targetDir: "", outputPath: "")
        XCTAssertFalse(s.isError)
    }

    func testFailureMapping() {
        XCTAssertEqual(ExportFailure(CollectError.cancelled), .cancelled)
        XCTAssertEqual(ExportFailure(CollectError.destinationExists("/x")), .destinationExists("/x"))
        XCTAssertEqual(ExportFailure(CollectError.packFailed(status: 1, output: "bad")), .pack("bad"))
        XCTAssertEqual(ExportFailure(CollectError.notEnoughSpace(needed: 5, free: 1)), .notEnoughSpace(needed: 5, free: 1))
        struct Other: Error {}
        if case .io = ExportFailure(Other()) {} else { XCTFail() }
    }

    func testStripZipAndProgressText() {
        XCTAssertEqual(ExportModel.stripZip("/a/X Project_export.zip"), "/a/X Project_export")
        XCTAssertEqual(ExportModel.stripZip("/a/X.ZIP"), "/a/X")
        XCTAssertEqual(ExportModel.stripZip("/a/X"), "/a/X")
        XCTAssertEqual(ExportText.progress(CollectProgress(phase: .copying, done: 3, total: 9)), "Exporting 3 of 9")
        XCTAssertEqual(ExportText.progress(CollectProgress(phase: .packing)), "Packing the archive…")
        XCTAssertEqual(ExportText.progress(nil), "")
    }

    func testDoneText() {
        var r = CollectResult(output: "/a/X Project_export")
        r.copiedFiles = 7
        XCTAssertEqual(ExportText.doneText(r), "Exported 7 files to “X Project_export”")
        r.failed = [CollectFailure(name: "a", path: "/a", reason: "r")]
        XCTAssertTrue(ExportText.doneText(r).contains("some files could not be copied"))
    }
}

@MainActor
final class ExportModelTests: XCTestCase {
    private var scratch = ""
    private var app: AppModel!
    private var model: ExportModel!
    private var setPath = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = try UIFixture.scratch("export")
        app = try makeModel()
        Localizer.shared.preference = .en           // AppModel resets it from settings
        model = app.export

        let fm = FileManager.default
        try fm.createDirectory(atPath: scratch + "/Song Project/Samples/Recorded", withIntermediateDirectories: true)
        try Data(String(repeating: "k", count: 1_000).utf8).write(to: URL(fileURLWithPath: scratch + "/Song Project/Samples/Recorded/kick.wav"))
        try fm.createDirectory(atPath: scratch + "/Elsewhere", withIntermediateDirectories: true)
        try Data(String(repeating: "h", count: 2_000).utf8).write(to: URL(fileURLWithPath: scratch + "/Elsewhere/hit.wav"))
        let refs = [
            UIFixture.sampleRef(rel: "Samples/Recorded/kick.wav", abs: "/old/kick.wav", type: 3),
            UIFixture.sampleRef(rel: "", abs: scratch + "/Elsewhere/hit.wav", type: 0),
            UIFixture.sampleRef(rel: "", abs: "/nonexistent/gone.wav", type: 0),
            UIFixture.sampleRef(rel: "", abs: "/nonexistent/gone2.wav", type: 0),
        ]
        setPath = try UIFixture.write(UIFixture.xml(refs: refs), to: scratch + "/Song Project/Song.als")
    }

    override func tearDown() {
        model.close()
        try? FileManager.default.removeItem(atPath: scratch)
        try? FileManager.default.removeItem(atPath: app.dataDir)
        Localizer.shared.preference = .system
        super.tearDown()
    }

    func testCountingShowsGroupsBeforeAnythingIsCopied() async throws {
        await model.open(path: setPath)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.readError)
        let g = Dictionary(uniqueKeysWithValues: model.groups.map { ($0.origin, $0) })
        XCTAssertEqual(g[.inProject]?.files, 1)
        XCTAssertEqual(g[.inProject]?.bytes, 1_000)
        XCTAssertEqual(g[.elsewhere]?.files, 1)
        XCTAssertEqual(g[.elsewhere]?.bytes, 2_000)
        XCTAssertEqual(g[.factoryPack]?.included, false, "factory packs are off by default")
        XCTAssertEqual(model.notFound.count, 2)
        XCTAssertEqual(ExportText.notFoundSummary(model.notFound.count), "2 files not found — left as they are")
        XCTAssertTrue(model.canExport)
        XCTAssertEqual(model.plan?.totalBytes, 3_000)
        XCTAssertEqual(model.targetDir, scratch + "/Song Project/Song Project_export")
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.targetDir), "nothing is created before Export")
    }

    func testTogglesReplanAndZipChangesTheOutput() async throws {
        await model.open(path: setPath)
        model.setIncluded(.elsewhere, false)
        XCTAssertEqual(model.plan?.totalBytes, 1_000)
        model.setIncluded(.factoryPack, true)
        XCTAssertEqual(model.groups.first { $0.origin == .factoryPack }?.included, true)
        model.setIncluded(.inProject, false)                    // not switchable
        XCTAssertEqual(model.plan?.copy.count, 1)
        model.setZip(true)
        XCTAssertEqual(model.outputPath, model.targetDir + ".zip")
        XCTAssertEqual(model.suggestedName, "Song Project_export.zip")
        XCTAssertEqual(model.suggestedFolder, scratch + "/Song Project")
    }

    func testExistingDestinationBlocksExportButNothingIsReplaced() async throws {
        await model.open(path: setPath)
        let taken = scratch + "/Taken"
        try FileManager.default.createDirectory(atPath: taken, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: URL(fileURLWithPath: taken + "/precious.txt"))
        model.setDestination(taken)
        XCTAssertTrue(model.destinationExists)
        XCTAssertFalse(model.canExport)
        await model.start()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: taken), ["precious.txt"])

        model.setDestination(scratch + "/Fresh.zip")            // a typed ".zip" name is accepted
        XCTAssertEqual(model.targetDir, scratch + "/Fresh")
        XCTAssertFalse(model.destinationExists)
    }

    func testExportToAFolderRemembersTheChoiceAndLeavesTheOriginalAlone() async throws {
        let before = [UIFixture.sha(setPath), UIFixture.sha(scratch + "/Song Project/Samples/Recorded/kick.wav"),
                      UIFixture.sha(scratch + "/Elsewhere/hit.wav")]
        await model.open(path: setPath)
        model.setIncluded(.factoryPack, true)
        model.setDestination(scratch + "/Out/Song Project_export")
        await model.start()

        XCTAssertEqual(model.phase, .done)
        let r = try XCTUnwrap(model.result)
        XCTAssertEqual(r.copiedFiles, 2)
        XCTAssertTrue(r.failed.isEmpty)
        let out = scratch + "/Out/Song Project_export"
        XCTAssertTrue(FileManager.default.fileExists(atPath: out + "/Song.als"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: out + "/Samples/Imported/hit.wav"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: out + "/Samples/Recorded/kick.wav"))
        XCTAssertEqual(app.toasts.count, 1, "one toast for the whole export")

        // The choice is persisted through mutateSettings.
        XCTAssertTrue(app.settings.collectFactoryPacks)
        XCTAssertFalse(app.settings.collectToZip)
        XCTAssertEqual(AppSettings.load(dir: app.dataDir).collectFactoryPacks, true)

        let after = [UIFixture.sha(setPath), UIFixture.sha(scratch + "/Song Project/Samples/Recorded/kick.wav"),
                     UIFixture.sha(scratch + "/Elsewhere/hit.wav")]
        XCTAssertEqual(before, after)
    }

    func testExportToAZipLeavesOnlyTheArchive() async throws {
        await model.open(path: setPath)
        model.setZip(true)
        model.setDestination(scratch + "/Out/Song Project_export")
        await model.start()
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.result?.output, scratch + "/Out/Song Project_export.zip")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch + "/Out"), ["Song Project_export.zip"])
        XCTAssertTrue(app.settings.collectToZip)
    }

    func testAnUnreadableSetIsReported() async throws {
        let bad = scratch + "/Bad Project/Bad.als"
        try FileManager.default.createDirectory(atPath: (bad as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: URL(fileURLWithPath: bad))
        await model.open(path: bad)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertNotNil(model.readError)
        XCTAssertFalse(model.canExport)
    }

    func testClosingResetsEverything() async throws {
        await model.open(path: setPath)
        model.close()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.plan)
        XCTAssertFalse(model.canExport)
    }
}
