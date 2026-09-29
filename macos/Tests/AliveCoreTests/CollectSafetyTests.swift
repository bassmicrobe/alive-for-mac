import XCTest
@testable import AliveCore

/// A set that came from somebody else is an untrusted document: Collect All must not be a way
/// to make the program copy private files or whole folders into an export.
final class CollectSafetyTests: XCTestCase {
    private struct Lab {
        let t: TempDir
        var set = SetEntry()
        var info = AlsInfo()
        var deps: [CollectDependency] = []
        var env = LiveEnvironment()
        var setDir: String { t.sub("Proj Project") }

        init(t: TempDir, extraRefs: (TempDir) -> [String] = { _ in [] }) {
            self.t = t
            t.write("Proj Project/Samples/kick.wav", "kick")
            t.write("Proj Project/Ableton Project Info/Project.cfg", "cfg")
            t.write("home/.ssh/id_rsa", "PRIVATE KEY")
            t.write("home/.ssh/key.wav", "hidden but named like audio")
            t.write("docs/notes.txt", "notes")
            t.mkdir("docs/folder")
            t.write("docs/folder/inside.wav", "x")
            t.write("outside/real.wav", "the real audio")
            t.write("outside/secret.txt", "SECRET")
            t.write("shared/hit.wav", "hit")
            symlink("Proj Project/Samples/link-real.wav", to: t.sub("outside/real.wav"))
            symlink("Proj Project/Samples/link-secret.wav", to: t.sub("outside/secret.txt"))
            symlink("Proj Project/Samples/link-ssh.wav", to: t.sub("home/.ssh/key.wav"))
            symlink("Proj Project/Samples/link-dir.wav", to: t.sub("docs/folder"))

            func ref(_ rel: String, _ abs: String, _ type: Int) -> String {
                Fx.fileRef(rel: rel, abs: abs, type: type, size: 1)
            }
            let refs = [
                ref("Samples/kick.wav", "/old/kick.wav", 3),
                ref("", t.sub("home/.ssh/id_rsa"), 0),
                ref("", t.sub("home/.ssh/key.wav"), 0),
                ref("", t.sub("docs/notes.txt"), 0),
                ref("", t.sub("docs/folder"), 0),
                ref("../home/.ssh/id_rsa", "/gone", 1),                 // reaches out of the project by ".."
                ref("Samples/link-real.wav", "/gone", 3),
                ref("Samples/link-secret.wav", "/gone", 3),
                ref("Samples/link-ssh.wav", "/gone", 3),
                ref("Samples/link-dir.wav", "/gone", 3),
                ref("", t.sub("shared/hit.wav"), 0),
            ] + extraRefs(t)
            let path = t.als("Proj Project/Song.als", RescueFx.set(devices: [], refs: refs))
            set.path = path
            set.name = "Song"
            info = AlsFile.read(path: path)
            deps = CollectScan.of(info, setDir: setDir, env: env)
        }

        private func symlink(_ rel: String, to target: String) {
            try? FileManager.default.createDirectory(atPath: (t.sub(rel) as NSString).deletingLastPathComponent,
                                                     withIntermediateDirectories: true)
            try? FileManager.default.createSymbolicLink(atPath: t.sub(rel), withDestinationPath: target)
        }

        func dep(refIndex i: Int) -> CollectDependency? { deps.first { $0.refIndexes.contains(i) } }
    }

    func testPrivateAndNonMediaFilesAreRefused() {
        let lab = Lab(t: makeTemp())
        XCTAssertNil(lab.info.error)
        XCTAssertEqual(lab.dep(refIndex: 0)?.origin, .inProject)
        XCTAssertNil(lab.dep(refIndex: 0)?.refusal)

        XCTAssertEqual(lab.dep(refIndex: 1)?.refusal, .hiddenFolder, "an ssh key by absolute path")
        XCTAssertEqual(lab.dep(refIndex: 2)?.refusal, .hiddenFolder, "media extension does not help inside a hidden folder")
        XCTAssertEqual(lab.dep(refIndex: 3)?.refusal, .notMedia, "a text file")
        XCTAssertEqual(lab.dep(refIndex: 4)?.refusal, .notRegularFile, "a whole folder")
        XCTAssertEqual(lab.dep(refIndex: 5)?.refusal, .hiddenFolder, "the same by a relative path with '..'")
        XCTAssertNil(lab.dep(refIndex: 10)?.refusal, "ordinary audio from elsewhere is still fine")
        XCTAssertEqual(lab.dep(refIndex: 10)?.origin, .elsewhere)
        XCTAssertEqual(lab.dep(refIndex: 4)?.size, 0, "a refused folder is not even counted")
    }

    func testASymlinkLeavingTheProjectIsTreatedAsFromElsewhereAndVetted() {
        let lab = Lab(t: makeTemp())
        let real = lab.dep(refIndex: 6)
        XCTAssertEqual(real?.origin, .elsewhere, "not 'in the project': it only looks like it")
        XCTAssertNil(real?.refusal)
        XCTAssertEqual(real?.size, Int64("the real audio".utf8.count))
        XCTAssertEqual(lab.dep(refIndex: 7)?.refusal, .notMedia, "a link to a secret text file")
        XCTAssertEqual(lab.dep(refIndex: 8)?.refusal, .hiddenFolder, "a link into ~/.ssh-like folder")
        XCTAssertEqual(lab.dep(refIndex: 9)?.refusal, .notRegularFile, "a link to a folder")
    }

    func testThePlanKeepsRefusedFilesOutAndSummarisesThem() {
        let lab = Lab(t: makeTemp())
        let plan = CollectAll.plan(set: lab.set, deps: lab.deps, options: CollectOptions(),
                                   targetDir: lab.t.sub("Out/Song Project_export"))
        XCTAssertEqual(plan.refused.count, 7)
        let copied = plan.copy.map(\.name).sorted()
        XCTAssertEqual(copied, ["hit.wav", "kick.wav", "link-real.wav"])
        XCTAssertEqual(plan.totalBytes, Int64("kick".utf8.count + "hit".utf8.count + "the real audio".utf8.count))
        XCTAssertEqual(plan.elsewhereFolders, [
            CollectSafety.realPath(lab.t.sub("outside")) ?? "",
            CollectSafety.realPath(lab.t.sub("shared")) ?? "",
        ].sorted(), "the person sees which folders the copy reaches into")
    }

    func testExportCopiesNothingPrivate() throws {
        let lab = Lab(t: makeTemp())
        let out = lab.t.sub("Out/Song Project_export")
        let plan = CollectAll.plan(set: lab.set, deps: lab.deps, options: CollectOptions(), targetDir: out)
        let result = try CollectAll.run(plan: plan, set: lab.set, info: lab.info)
        XCTAssertEqual(result.copiedFiles, 3)
        XCTAssertTrue(result.failed.isEmpty)

        let tree = (FileManager.default.subpaths(atPath: out) ?? []).sorted()
        XCTAssertTrue(tree.contains("Samples/kick.wav"))
        XCTAssertTrue(tree.contains("Samples/Imported/link-real.wav"), "the link's target was collected, as a file")
        XCTAssertTrue(tree.contains("Samples/Imported/hit.wav"))
        for forbidden in ["id_rsa", "key.wav", "notes.txt", "inside.wav", "secret", "link-secret.wav", "link-ssh.wav"] {
            XCTAssertFalse(tree.contains { $0.contains(forbidden) }, "\(forbidden) must not be in the export: \(tree)")
        }
        XCTAssertEqual(try String(contentsOfFile: out + "/Samples/Imported/link-real.wav"), "the real audio")
        // The refused references stay as they were in the original.
        let now = AlsFile.read(path: out + "/Song.als")
        XCTAssertEqual(now.files[1], lab.info.files[1])
        XCTAssertEqual(now.files[7], lab.info.files[7])
    }

    func testALinkRetargetedAfterThePlanIsNotFollowed() throws {
        let lab = Lab(t: makeTemp())
        let out = lab.t.sub("Out/Song Project_export")
        let plan = CollectAll.plan(set: lab.set, deps: lab.deps, options: CollectOptions(), targetDir: out)
        let link = lab.t.sub("Proj Project/Samples/link-real.wav")
        try FileManager.default.removeItem(atPath: link)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: lab.t.sub("outside/secret.txt"))
        let result = try CollectAll.run(plan: plan, set: lab.set, info: lab.info)
        XCTAssertEqual(result.failed.map(\.name), ["link-real.wav"])
        XCTAssertFalse((FileManager.default.subpaths(atPath: out) ?? []).contains { $0.contains("link-real") })
    }

    func testBundleSizeCountsEveryLevelAndSkipsLinks() {
        let t = makeTemp()
        t.write("Proj Project/Ableton Project Info/p.cfg")
        t.write("bund/Thing.amxd/a/b/c/d/e/f/g/deep.bin", String(repeating: "z", count: 500))
        t.write("bund/Thing.amxd/top.maxpat", String(repeating: "z", count: 20))
        try? FileManager.default.createSymbolicLink(atPath: t.sub("bund/Thing.amxd/loop"), withDestinationPath: t.sub("bund"))
        let ref = Fx.fileRef(parent: "MxPatchRef", rel: "", abs: t.sub("bund/Thing.amxd"), type: 0)
        let path = t.als("Proj Project/Song.als", RescueFx.set(devices: [], refs: [ref]))
        let deps = CollectScan.of(AlsFile.read(path: path), setDir: t.sub("Proj Project"), env: LiveEnvironment())
        XCTAssertEqual(deps.first?.size, 520, "the old depth limit of 4 undercounted this and 'fits' lied")
        XCTAssertNil(deps.first?.refusal)
    }

    func testTheRulesOnPathsThemselves() {
        let t = makeTemp()
        let home = t.mkdir("home")
        t.write("home/Library/Keychains/login.keychain-db")
        t.write("home/Library/Keychains/x.wav")
        t.write("home/Music/ok.wav")
        t.write("home/.aws/credentials")
        t.write("home/Music/notes.pdf")
        XCTAssertEqual(CollectSafety.refusal(forRealPath: t.sub("home/Library/Keychains/x.wav"), home: home), .sensitiveLocation)
        XCTAssertEqual(CollectSafety.refusal(forRealPath: t.sub("home/.aws/credentials"), home: home), .hiddenFolder)
        XCTAssertEqual(CollectSafety.refusal(forRealPath: t.sub("home/Music/notes.pdf"), home: home), .notMedia)
        XCTAssertNil(CollectSafety.refusal(forRealPath: t.sub("home/Music/ok.wav"), home: home))
        // Inside the project only the kind of thing matters, and a project may itself sit in a hidden folder.
        t.write("home/.cache/My Project/Samples/odd.xyz")
        let project = t.sub("home/.cache/My Project")
        XCTAssertNil(CollectSafety.refusal(forRealPath: project + "/Samples/odd.xyz", projectRoot: project, home: home))
        t.write("home/.cache/My Project/.git/config")
        XCTAssertEqual(CollectSafety.refusal(forRealPath: project + "/.git/config", projectRoot: project, home: home), .hiddenFolder)
    }

    func testPackingSurvivesAFolderNameThatLooksLikeAnOption() throws {
        let t = makeTemp()
        t.write("-dash/file.txt", "x")
        let previous = FileManager.default.currentDirectoryPath
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(t.path))
        defer { _ = FileManager.default.changeCurrentDirectoryPath(previous) }
        XCTAssertNoThrow(try CollectAll.pack(folder: "-dash", into: t.sub("out.zip"), isCancelled: { false }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: t.sub("out.zip")))
    }
}

/// The probe is a file the program creates inside somebody's project folder; it must never
/// replace or delete anything that is not its own.
final class ProbeSafetyTests: XCTestCase {
    private func session(_ t: TempDir, dataDir: String) throws -> (RescueSession, String) {
        let als = t.als("Song Project/Song.als", RescueFx.set(devices: [RescueFx.serum, RescueFx.proQ]))
        var set = SetEntry()
        set.path = als
        set.name = "Song"
        return (RescueSession(set: set, inventory: nil, dataDir: dataDir, logFiles: { [] }), als)
    }

    func testAnExistingFileAtTheProbePathIsNeverOverwrittenOrDeleted() throws {
        let t = makeTemp()
        let home = t.mkdir("home")
        let (s, _) = try session(t, dataDir: home)
        let mine = t.write("Song Project/Song.alive-probe.als", "somebody's own file")

        let probe = try s.prepare(disable: [s.targets[0]])
        XCTAssertNotEqual(probe, mine)
        XCTAssertTrue(RescueProbe.isProbe(probe), "the new name still counts as a probe for the catalog filter")
        XCTAssertEqual(try String(contentsOfFile: mine), "somebody's own file")
        XCTAssertNil(AlsFile.read(path: probe).error)

        s.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: probe))
        XCTAssertEqual(try String(contentsOfFile: mine), "somebody's own file", "cancel removed only what it made")
        XCTAssertEqual(RescueProbe.journal(dir: home), [])
    }

    func testAFailedProbeWriteDoesNotRemoveTheFileThatWasThere() throws {
        let t = makeTemp()
        let home = t.mkdir("home")
        let (s, als) = try session(t, dataDir: home)
        let mine = t.write("Song Project/Song.alive-probe.als", "keep me")
        XCTAssertThrowsError(try AlsPatch.neutralize(src: als, dst: mine, uids: [s.targets[0].uid]))
        XCTAssertEqual(try String(contentsOfFile: mine), "keep me")
    }

    func testACancelledWriteLeavesNoProbe() throws {
        let t = makeTemp()
        let home = t.mkdir("home")
        let (s, _) = try session(t, dataDir: home)
        XCTAssertThrowsError(try s.writeProbe(disable: [s.targets[0]], isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual((try FileManager.default.contentsOfDirectory(atPath: t.sub("Song Project"))).sorted(), ["Song.als"])
        XCTAssertEqual(RescueProbe.journal(dir: home), [])
    }

    func testTheJournalCannotMakeCleanupDeleteFoldersLinksOrRelativePaths() throws {
        let t = makeTemp()
        let home = t.mkdir("home")
        // A folder whose name ends in the probe suffix, with a precious file inside.
        let folder = t.write("Proj/Trap.alive-probe.als/precious.txt", "precious")
        let folderPath = t.sub("Proj/Trap.alive-probe.als")
        // A symlink named like a probe, pointing at a real set.
        let realSet = t.als("Proj/Real.als", Fx.simpleSet())
        let link = t.sub("Proj/Link.alive-probe.als")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: realSet)
        // A plain file with the suffix that is not a gzip or XML document.
        let notASet = t.write("Proj/Notes.alive-probe.als", "my diary")
        // A genuine probe of ours, and a relative entry.
        let genuine = t.write("Proj/Song.alive-probe.als", "<?xml version=\"1.0\"?><Ableton/>")
        let journal = [folderPath, link, notASet, "relative/Song.alive-probe.als", genuine]
        try (journal.joined(separator: "\n") + "\n").write(toFile: RescueProbe.journalPath(dir: home),
                                                            atomically: true, encoding: .utf8)

        XCTAssertEqual(RescueProbe.cleanupStale(dir: home), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder))
        XCTAssertTrue(FileManager.default.fileExists(atPath: realSet))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link))
        XCTAssertEqual(try String(contentsOfFile: notASet), "my diary")
        XCTAssertFalse(FileManager.default.fileExists(atPath: genuine))
        XCTAssertEqual(RescueProbe.journal(dir: home), [])

        RescueProbe.drop(folderPath, dir: home)
        RescueProbe.drop(notASet, dir: home)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder))
        XCTAssertEqual(try String(contentsOfFile: notASet), "my diary")
    }
}

/// A cancelled scan must not publish, or write the caches, from a half-built catalog.
final class ScanCancelTests: XCTestCase {
    func testACancelAfterTheParsePhasePublishesNothing() throws {
        let t = makeTemp()
        t.als("Lib/A Project/A.als", Fx.simpleSet())
        let data = t.mkdir("data")
        let idx = ProjectIndex(dir: data, home: t.mkdir("home"), applicationsDirs: [], settings: Settings())
        let armed = Counter()
        let calls = Counter()
        let stats = idx.scan(roots: [t.sub("Lib")], progress: { done, total, _ in
            if total > 0, done == total { armed.bump() }        // the parse phase has just finished
        }, isCancelled: {
            guard armed.value > 0 else { return false }
            calls.bump()
            return calls.value >= 2                             // the later phases see the cancel
        })
        XCTAssertTrue(stats.cancelled)
        XCTAssertTrue(idx.sets.isEmpty, "nothing half-built is published")
        XCTAssertFalse(FileManager.default.fileExists(atPath: IndexCache.path(dir: data)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: Activity.cachePath(dir: data)))
    }

    func testBlockingWorkRunsOffThePoolAndHonoursCancellation() async throws {
        let started = Counter()
        let task = Task { () -> Bool in
            await BlockingWork.run { isCancelled in
                started.bump()
                for _ in 0..<500 where !isCancelled() { Thread.sleep(forTimeInterval: 0.01) }
                return isCancelled()
            }
        }
        while started.value == 0 { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        let sawCancel = await task.value
        XCTAssertTrue(sawCancel)
    }
}
