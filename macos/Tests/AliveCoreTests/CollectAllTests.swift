import XCTest
@testable import AliveCore

/// A scratch library with one set that pulls samples from every origin.
private struct Library {
    let t: TempDir
    var env = LiveEnvironment()
    var set = SetEntry()
    var info = AlsInfo()
    var deps: [CollectDependency] = []
    var sourceFiles: [String] = []

    var setDir: String { t.sub("Proj Project") }

    static let sizes: [String: Int] = [
        "kick": 1_000, "elsewhere": 2_000, "elsewhereClash": 3_000, "other": 4_000,
        "user": 5_000, "pack": 6_000, "bundle": 700,
    ]

    init(t: TempDir) {
        self.t = t
        func bytes(_ n: Int) -> String { String(repeating: "a", count: n) }
        let s = Library.sizes

        t.write("Proj Project/Samples/Recorded/kick.wav", bytes(s["kick"]!))
        t.write("Proj Project/Ableton Project Info/Project.cfg", "cfg")
        t.write("Elsewhere/hit.wav", bytes(s["elsewhere"]!))
        t.write("Elsewhere2/hit.wav", bytes(s["elsewhereClash"]!))          // same name, other folder
        t.write("Other Project/Samples/o.wav", bytes(s["other"]!))
        t.write("UL/Presets/u.wav", bytes(s["user"]!))
        t.write("Packs/Acme/Loops/l.wav", bytes(s["pack"]!))
        t.write("Elsewhere/Thing.amxd/main.maxpat", bytes(300))
        t.write("Elsewhere/Thing.amxd/extra.bin", bytes(400))

        env.userLibrary = t.sub("UL")
        env.builtin = t.sub("Live/Builtin")
        env.coreLibrary = t.sub("Live/Core")
        env.setPack("Acme", t.sub("Packs/Acme"))

        func ref(_ i: Int, parent: String = "SampleRef", rel: String, abs: String, type: Int, pack: String = "") -> String {
            Fx.fileRef(parent: parent, rel: rel, abs: abs, type: type, pack: pack, size: i)
        }
        let refs = [
            ref(1, rel: "Samples/Recorded/kick.wav", abs: "/old/kick.wav", type: 3),
            ref(2, rel: "Samples/Recorded/kick.wav", abs: "/old/kick.wav", type: 3),               // same file again
            ref(3, rel: "", abs: t.sub("Elsewhere/hit.wav"), type: 0),
            ref(4, rel: "", abs: t.sub("Elsewhere2/hit.wav"), type: 0),
            ref(5, rel: "", abs: t.sub("Other Project/Samples/o.wav"), type: 0),
            ref(6, rel: "Presets/u.wav", abs: "/gone/u.wav", type: 6),
            ref(7, rel: "Loops/l.wav", abs: "/gone/l.wav", type: 5, pack: "Acme"),
            ref(8, rel: "", abs: "/nonexistent/gone.wav", type: 0),
            ref(9, parent: "MxPatchRef", rel: "", abs: t.sub("Elsewhere/Thing.amxd"), type: 0),
            ref(10, parent: "OriginalFileRef", rel: "", abs: "/never/copied.adv", type: 0),         // provenance only
        ]
        let path = t.als("Proj Project/Song.als", RescueFx.set(devices: [RescueFx.serum], refs: refs))
        set.path = path
        set.name = "Song"
        info = AlsFile.read(path: path)
        deps = CollectScan.of(info, setDir: setDir, env: env)
        sourceFiles = [path, t.sub("Proj Project/Samples/Recorded/kick.wav"), t.sub("Elsewhere/hit.wav"),
                       t.sub("Elsewhere2/hit.wav"), t.sub("Other Project/Samples/o.wav"), t.sub("UL/Presets/u.wav"),
                       t.sub("Packs/Acme/Loops/l.wav"), t.sub("Proj Project/Ableton Project Info/Project.cfg")]
    }

    func hashes() -> [String] { sourceFiles.map(RescueFx.sha) }

    func dep(_ origin: CollectOrigin, _ name: String) -> CollectDependency? {
        deps.first { $0.origin == origin && $0.name == name }
    }
}

final class CollectScanTests: XCTestCase {
    func testEveryOriginIsClassifiedAndReferencesAreFolded() {
        let lib = Library(t: makeTemp())
        XCTAssertNil(lib.info.error)
        XCTAssertEqual(lib.info.files.count, 10)

        let kick = lib.dep(.inProject, "kick.wav")
        XCTAssertEqual(kick?.refIndexes, [0, 1], "two references, one file")
        XCTAssertEqual(kick?.size, Int64(Library.sizes["kick"]!))
        XCTAssertEqual(lib.dep(.elsewhere, "hit.wav")?.size, 2_000)
        XCTAssertEqual(lib.deps.filter { $0.name == "hit.wav" }.count, 2, "same name, different files")
        XCTAssertEqual(lib.dep(.otherProject, "o.wav")?.size, 4_000)
        XCTAssertEqual(lib.dep(.userLibrary, "u.wav")?.size, 5_000)
        XCTAssertEqual(lib.dep(.factoryPack, "l.wav")?.packName, "Acme")
        XCTAssertEqual(lib.dep(.elsewhere, "Thing.amxd")?.size, 700, "a bundle folder weighs what is inside")
        XCTAssertTrue(lib.dep(.elsewhere, "Thing.amxd")?.isDevice ?? false)
        XCTAssertEqual(lib.deps.filter { $0.origin == .missing }.count, 1)
        XCTAssertFalse(lib.deps.contains { $0.path.hasSuffix("copied.adv") }, "provenance references are not dependencies")
    }

    func testUnderMatchesWholeComponentsOnly() {
        XCTAssertTrue(CollectScan.under("/a/Samples/x.wav", "/a/Samples"))
        XCTAssertFalse(CollectScan.under("/a/Samples2/x.wav", "/a/Samples"))
        XCTAssertFalse(CollectScan.under("/a/Samples", "/a/Samples"))
        XCTAssertTrue(CollectScan.under("/A/samples/X.wav", "/a/Samples/"))
        XCTAssertFalse(CollectScan.under("/a/x", ""))
        XCTAssertEqual(CollectScan.relative(root: "/a/b", path: "/a/b/c/d.wav"), "c/d.wav")
        XCTAssertTrue(CollectScan.inSomeProject("/x/Foo Project/Samples/Recorded/a.wav"))
        XCTAssertFalse(CollectScan.inSomeProject("/x/y/z/w/v/a.wav"))
    }
}

final class CollectPlanTests: XCTestCase {
    func testGroupsCountFilesAndBytesBeforeAnythingIsCopied() {
        let lib = Library(t: makeTemp())
        var opt = CollectOptions()
        let g = CollectAll.groups(lib.deps, opt)
        XCTAssertEqual(g.map(\.origin), [.inProject, .elsewhere, .otherProject, .userLibrary, .factoryPack])
        XCTAssertEqual(g.map(\.files), [1, 3, 1, 1, 1])
        XCTAssertEqual(g.map(\.bytes), [1_000, 2_000 + 3_000 + 700, 4_000, 5_000, 6_000])
        XCTAssertEqual(g.map(\.included), [true, true, true, true, false], "factory packs are off by default")
        opt.fromElsewhere = false
        XCTAssertEqual(CollectAll.groups(lib.deps, opt)[1].included, false)
    }

    func testPlanHonoursTheOptions() {
        let lib = Library(t: makeTemp())
        var opt = CollectOptions()
        var plan = CollectAll.plan(set: lib.set, deps: lib.deps, options: opt, targetDir: lib.t.sub("Out/X"))
        XCTAssertEqual(plan.copy.count, 6)                        // project + 3 elsewhere + other + user
        XCTAssertEqual(plan.skipped.map(\.name), ["l.wav"])
        XCTAssertEqual(plan.notFound.count, 1)
        XCTAssertEqual(plan.totalBytes, 1_000 + 2_000 + 3_000 + 700 + 4_000 + 5_000)
        XCTAssertFalse(plan.zip)
        XCTAssertEqual(plan.outputPath, lib.t.sub("Out/X"))

        opt.fromFactoryPacks = true
        opt.fromElsewhere = false
        opt.fromOtherProjects = false
        opt.fromUserLibrary = false
        opt.toZip = true
        plan = CollectAll.plan(set: lib.set, deps: lib.deps, options: opt, targetDir: lib.t.sub("Out/X"))
        XCTAssertEqual(plan.copy.map(\.name).sorted(), ["kick.wav", "l.wav"])
        XCTAssertEqual(plan.totalBytes, 7_000)
        XCTAssertEqual(plan.outputPath, lib.t.sub("Out/X.zip"))
        XCTAssertEqual(plan.zipPath, plan.targetDir + ".zip")
    }

    func testDestinationsRewritesAndNameClashes() {
        let lib = Library(t: makeTemp())
        let plan = CollectAll.plan(set: lib.set, deps: lib.deps, options: CollectOptions(), targetDir: lib.t.sub("Out/X"))
        let kick = lib.dep(.inProject, "kick.wav")!
        XCTAssertEqual(plan.dest[kick.id], "Samples/Recorded/kick.wav", "the project structure is reproduced")
        XCTAssertNil(plan.rewrites[0], "in-project references are right as they are")
        XCTAssertNil(plan.rewrites[1])

        let hits = lib.deps.filter { $0.name == "hit.wav" }.compactMap { plan.dest[$0.id] }.sorted()
        XCTAssertEqual(hits, ["Samples/Imported/hit 2.wav", "Samples/Imported/hit.wav"])
        XCTAssertEqual(plan.dest[lib.dep(.elsewhere, "Thing.amxd")!.id], "Devices/Thing.amxd")
        XCTAssertEqual(plan.dest[lib.dep(.userLibrary, "u.wav")!.id], "Samples/Imported/u.wav")

        let user = lib.dep(.userLibrary, "u.wav")!
        let nr = plan.rewrites[user.refIndexes[0]]
        XCTAssertEqual(nr?.relativePath, "Samples/Imported/u.wav")
        XCTAssertEqual(nr?.relativePathType, 3)
        XCTAssertEqual(nr?.clearPack, true)
        XCTAssertEqual(nr?.absolutePath, "", "completed at run time from the final target")
    }

    func testPlanIsIndependentOfDependencyOrderWhenNamesClash() {
        // An external "kick.wav" listed BEFORE the in-project one must not steal its path.
        let t = makeTemp()
        t.write("P Project/Samples/Imported/kick.wav", "in")
        t.write("Ext/kick.wav", "ext")
        var set = SetEntry()
        set.path = t.sub("P Project/S.als")
        set.name = "S"
        func dep(_ id: Int, _ path: String, _ origin: CollectOrigin) -> CollectDependency {
            var rr = ResolvedRef(ref: FileRefInfo())
            rr.resolvedPath = path
            var d = CollectDependency(resolved: rr)
            d.id = id; d.origin = origin; d.size = 1; d.refIndexes = [id]
            return d
        }
        let deps = [dep(0, t.sub("Ext/kick.wav"), .elsewhere), dep(1, t.sub("P Project/Samples/Imported/kick.wav"), .inProject)]
        let plan = CollectAll.plan(set: set, deps: deps, options: CollectOptions(), targetDir: t.sub("Out"))
        XCTAssertEqual(plan.dest[1], "Samples/Imported/kick.wav")
        XCTAssertEqual(plan.dest[0], "Samples/Imported/kick 2.wav")
    }

    func testFreeTargetSkipsTakenFoldersAndArchives() {
        let lib = Library(t: makeTemp())
        let first = CollectAll.freeTarget(for: lib.set)
        XCTAssertEqual(first, lib.setDir + "/Song Project_export")
        lib.t.mkdir("Proj Project/Song Project_export")
        lib.t.write("Proj Project/Song Project_export 2.zip")
        XCTAssertEqual(CollectAll.freeTarget(for: lib.set), lib.setDir + "/Song Project_export 3")
    }

    func testOptionsRoundTripThroughSettings() {
        var s = Settings()
        var o = CollectOptions()
        o.fromElsewhere = false; o.fromFactoryPacks = true; o.toZip = true
        o.store(in: &s)
        XCTAssertEqual(CollectOptions(settings: s), o)
        XCTAssertTrue(CollectOptions().wants(.inProject))
        XCTAssertFalse(CollectOptions().wants(.missing))
    }

    func testFitsDoublesTheNeedInZipMode() {
        var plan = CollectPlan()
        plan.totalBytes = 600
        plan.freeBytes = 1_000
        XCTAssertTrue(plan.fits)
        plan.zip = true
        XCTAssertFalse(plan.fits)
    }
}

final class CollectRunTests: XCTestCase {
    private func run(_ lib: Library, _ opt: CollectOptions = CollectOptions(), target: String? = nil,
                     cancelAfter: Int? = nil) throws -> (CollectResult, CollectPlan) {
        let plan = CollectAll.plan(set: lib.set, deps: lib.deps, options: opt, targetDir: target ?? lib.t.sub("Out/Song Project_export"))
        var seen = 0
        let result = try CollectAll.run(plan: plan, set: lib.set, info: lib.info, progress: { _ in seen += 1 },
                                        isCancelled: { cancelAfter.map { seen >= $0 } ?? false })
        return (result, plan)
    }

    func testFolderExportHasLivesCollectedLayoutAndAPatchedSet() throws {
        let lib = Library(t: makeTemp())
        let hashes = lib.hashes()
        let (result, plan) = try run(lib)

        let out = plan.targetDir
        XCTAssertEqual(result.output, out)
        XCTAssertEqual(result.copiedFiles, 6)
        XCTAssertTrue(result.failed.isEmpty)
        for rel in ["Song.als", "Samples/Recorded/kick.wav", "Samples/Imported/hit.wav", "Samples/Imported/hit 2.wav",
                    "Samples/Imported/o.wav", "Samples/Imported/u.wav", "Devices/Thing.amxd/main.maxpat",
                    "Devices/Thing.amxd/extra.bin", "Ableton Project Info/Project.cfg"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: out + "/" + rel), rel)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out + "/Samples/Imported/l.wav"), "factory packs are off")

        // The collected set: same number of references, the external ones now inside the project.
        let now = AlsFile.read(path: out + "/Song.als")
        XCTAssertNil(now.error)
        XCTAssertEqual(now.files.count, lib.info.files.count)
        XCTAssertEqual(now.files[0], lib.info.files[0], "in-project reference untouched")
        XCTAssertEqual(now.files[5].relativePath, "Samples/Imported/u.wav")
        XCTAssertEqual(now.files[5].absolutePath, out + "/Samples/Imported/u.wav")
        XCTAssertEqual(now.files[5].relativePathType, 3)
        XCTAssertEqual(now.files[8].relativePath, "Devices/Thing.amxd")
        XCTAssertEqual(now.files[6], lib.info.files[6], "a skipped pack reference is left as it was")
        XCTAssertEqual(now.files[7], lib.info.files[7], "a missing file's reference is left as it was")
        XCTAssertEqual(now.files[9], lib.info.files[9])

        // Every reference now resolves from the collected set's own folder.
        var env = LiveEnvironment()
        env.userLibrary = "/nonexistent"
        for i in [0, 2, 3, 4, 5, 8] {
            let r = RefResolver.resolve(now.files[i], projectDir: out, env: env)
            XCTAssertEqual(r.status, .found, "\(i) \(now.files[i].relativePath)")
            XCTAssertTrue(r.resolvedPath.hasPrefix(out), r.resolvedPath)
        }

        XCTAssertEqual(lib.hashes(), hashes, "nothing of the original moved or changed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.set.path + ".zip"))
    }

    func testProjectInfoIsCreatedEmptyWhenTheOriginalHasNone() throws {
        let lib = Library(t: makeTemp())
        try FileManager.default.removeItem(atPath: lib.t.sub("Proj Project/Ableton Project Info"))
        let (_, plan) = try run(lib)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.targetDir + "/Ableton Project Info", isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testFactoryPacksWhenAsked() throws {
        let lib = Library(t: makeTemp())
        var opt = CollectOptions()
        opt.fromFactoryPacks = true
        let (result, plan) = try run(lib, opt)
        XCTAssertEqual(result.copiedFiles, 7)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.targetDir + "/Samples/Imported/l.wav"))
        XCTAssertEqual(AlsFile.read(path: plan.targetDir + "/Song.als").files[6].livePackName, "", "no longer from a pack")
    }

    func testZipExportLeavesOnlyTheArchive() throws {
        let lib = Library(t: makeTemp())
        let hashes = lib.hashes()
        var opt = CollectOptions()
        opt.toZip = true
        var phases: [CollectProgress.Phase] = []
        let plan = CollectAll.plan(set: lib.set, deps: lib.deps, options: opt, targetDir: lib.t.sub("Out/Song Project_export"))
        let result = try CollectAll.run(plan: plan, set: lib.set, info: lib.info, progress: { phases.append($0.phase) })

        XCTAssertEqual(result.output, plan.targetDir + ".zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.targetDir), "no folder is left behind")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: lib.t.sub("Out")), ["Song Project_export.zip"])
        XCTAssertTrue(phases.contains(.packing))

        // Unpack next to it: the archive carries the project folder as its top level.
        let unpacked = lib.t.mkdir("Unpacked")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", result.output, unpacked]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        let root = unpacked + "/Song Project_export"
        XCTAssertTrue(FileManager.default.fileExists(atPath: root + "/Song.als"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root + "/Samples/Imported/u.wav"))
        XCTAssertNil(AlsFile.read(path: root + "/Song.als").error)
        XCTAssertEqual(lib.hashes(), hashes)
    }

    func testAnUnreadableFileIsReportedAndItsReferenceKeptAsItWas() throws {
        let lib = Library(t: makeTemp())
        let bad = lib.t.sub("UL/Presets/u.wav")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: bad)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: bad) }

        let (result, plan) = try run(lib)
        XCTAssertEqual(result.failed.map(\.name), ["u.wav"])
        XCTAssertEqual(result.copiedFiles, 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.targetDir + "/Samples/Imported/u.wav"))
        let now = AlsFile.read(path: plan.targetDir + "/Song.als")
        XCTAssertEqual(now.files[5], lib.info.files[5], "no reference points at a file that is not in the copy")
        XCTAssertEqual(now.files[2].relativePath, "Samples/Imported/hit.wav", "the others were still collected")
    }

    func testCancelRemovesWhatTheRunCreated() throws {
        let lib = Library(t: makeTemp())
        let hashes = lib.hashes()
        XCTAssertThrowsError(try run(lib, cancelAfter: 2)) { XCTAssertEqual($0 as? CollectError, .cancelled) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.t.sub("Out/Song Project_export")))
        XCTAssertEqual(lib.hashes(), hashes)

        var opt = CollectOptions()
        opt.toZip = true
        XCTAssertThrowsError(try run(lib, opt, cancelAfter: 1)) { XCTAssertEqual($0 as? CollectError, .cancelled) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.t.sub("Out/Song Project_export.zip")))
    }

    func testAnExistingDestinationIsNeverMergedOrOverwritten() throws {
        let lib = Library(t: makeTemp())
        let dest = lib.t.mkdir("Out/Song Project_export")
        lib.t.write("Out/Song Project_export/precious.txt", "keep")
        XCTAssertThrowsError(try run(lib, target: dest)) { XCTAssertEqual($0 as? CollectError, .destinationExists(dest)) }
        XCTAssertEqual(try String(contentsOfFile: dest + "/precious.txt"), "keep")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dest), ["precious.txt"])

        var opt = CollectOptions()
        opt.toZip = true
        let zip = lib.t.write("Out/Song Project_export 2.zip", "old zip")
        XCTAssertThrowsError(try run(lib, opt, target: lib.t.sub("Out/Song Project_export 2"))) {
            XCTAssertEqual($0 as? CollectError, .destinationExists(zip))
        }
        XCTAssertEqual(try String(contentsOfFile: zip), "old zip")
    }

    func testNotEnoughSpaceIsRefusedBeforeCopying() throws {
        let lib = Library(t: makeTemp())
        var plan = CollectAll.plan(set: lib.set, deps: lib.deps, options: CollectOptions(), targetDir: lib.t.sub("Out/X"))
        plan.freeBytes = 10
        XCTAssertThrowsError(try CollectAll.run(plan: plan, set: lib.set, info: lib.info)) {
            guard case .notEnoughSpace(let needed, let free)? = $0 as? CollectError else { return XCTFail("\($0)") }
            XCTAssertEqual(needed, plan.totalBytes)
            XCTAssertEqual(free, 10)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.targetDir))
    }

    func testDriftedReferenceNumberingAbortsAndCleansUp() throws {
        let lib = Library(t: makeTemp())
        var info = lib.info
        info.files.append(FileRefInfo())                        // the parser "saw" one more than the text has
        let plan = CollectAll.plan(set: lib.set, deps: lib.deps, options: CollectOptions(), targetDir: lib.t.sub("Out/X"))
        XCTAssertThrowsError(try CollectAll.run(plan: plan, set: lib.set, info: info)) {
            guard case .setNotWritten? = $0 as? CollectError else { return XCTFail("\($0)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.targetDir))
    }

    func testFreeSpaceOfANonexistentDestinationUsesItsNearestFolder() {
        let t = makeTemp()
        XCTAssertGreaterThan(CollectAll.freeSpace(near: t.sub("does/not/exist/yet")), 0)
    }
}
