import XCTest
@testable import AliveCore

final class SampleScanTests: XCTestCase {
    private func ref(container: String = "SampleRef", rel: String = "", abs: String = "", type: Int = 0,
                     pack: String = "", size: Int64 = 0) -> FileRefInfo {
        var r = FileRefInfo()
        r.container = container
        r.relativePath = rel
        r.absolutePath = abs
        r.relativePathType = type
        r.livePackName = pack
        r.originalFileSize = size
        return r
    }

    private func env(_ t: TempDir) -> LiveEnvironment {
        var e = LiveEnvironment()
        e.userLibrary = t.mkdir("User Library")
        e.builtin = t.mkdir("Live/Builtin")
        e.coreLibrary = t.mkdir("Live/Core Library")
        e.setPack("Drone Lab", t.mkdir("Packs/Drone Lab"))
        return e
    }

    func testOriginsAreCheckedInOrder() {
        let t = makeTemp("scan")
        let e = env(t)
        let setDir = t.mkdir("Music/Song Project")
        let inProject = SampleFixtures.put(SampleFixtures.wav(), at: setDir + "/Samples/Recorded/rec.wav")
        let pack = SampleFixtures.put(SampleFixtures.wav(), at: t.sub("Packs/Drone Lab/Samples/pad.wav"))
        let core = SampleFixtures.put(SampleFixtures.wav(), at: t.sub("Live/Core Library/Samples/core.wav"))
        let user = SampleFixtures.put(SampleFixtures.wav(), at: t.sub("User Library/Samples/mine.wav"))
        let other = SampleFixtures.put(SampleFixtures.wav(), at: t.sub("Music/Other Project/Samples/x.wav"))
        let plain = SampleFixtures.put(SampleFixtures.wav(), at: t.sub("Downloads/y.wav"))
        // A project that lies inside the User Library is still "in the project".
        let nestedSetDir = t.mkdir("User Library/Projects/Nested Project")
        let nested = SampleFixtures.put(SampleFixtures.wav(), at: nestedSetDir + "/z.wav")

        var info = AlsInfo()
        info.files = [
            ref(abs: inProject), ref(abs: pack), ref(abs: core), ref(abs: user), ref(abs: other), ref(abs: plain),
            ref(abs: t.sub("Gone/lost.wav")),
        ]
        let deps = SampleScan.of(info, setDir: setDir, env: e)
        XCTAssertEqual(deps.map(\.origin), [.inProject, .factoryPack, .factoryPack, .userLibrary, .otherProject, .elsewhere, .missing])
        XCTAssertEqual(deps[1].packName, "Drone Lab")
        XCTAssertEqual(deps[2].packName, "Core Library")
        XCTAssertEqual(deps[0].size, Int64(SampleFixtures.wav().count))
        XCTAssertEqual(deps[6].size, 0)

        var nestedInfo = AlsInfo()
        nestedInfo.files = [ref(abs: nested)]
        XCTAssertEqual(SampleScan.of(nestedInfo, setDir: nestedSetDir, env: e).first?.origin, .inProject)
    }

    func testRelativeTypesDecideOriginEvenWhenTheFileIsLooselyPlaced() {
        let t = makeTemp("scan")
        let e = env(t)
        let setDir = t.mkdir("Music/Song Project")
        SampleFixtures.put(SampleFixtures.wav(), at: t.sub("User Library/Samples/mine.wav"))
        SampleFixtures.put(SampleFixtures.wav(), at: t.sub("Live/Builtin/b.wav"))
        var info = AlsInfo()
        info.files = [ref(rel: "Samples/mine.wav", type: 6), ref(rel: "b.wav", type: 7),
                      ref(rel: "Samples/none.wav", type: 5, pack: "Ghost Pack")]
        let deps = SampleScan.of(info, setDir: setDir, env: e)
        XCTAssertEqual(deps.map(\.origin), [.userLibrary, .factoryPack, .missing])
        XCTAssertEqual(deps[1].packName, "Core Library")
        XCTAssertEqual(deps[2].resolved.status, .missingPack)
        XCTAssertEqual(deps[2].packName, "Ghost Pack")
    }

    func testReferencesToOneFileFoldIntoOneDependency() {
        let t = makeTemp("scan")
        let e = env(t)
        let setDir = t.mkdir("Music/Song Project")
        let file = SampleFixtures.put(SampleFixtures.wav(), at: t.sub("Downloads/loop.wav"))
        var info = AlsInfo()
        info.files = [
            ref(abs: file), ref(abs: file), ref(abs: ""), ref(container: "FilePresetRef", abs: t.sub("Downloads/preset.adg")),
            ref(rel: "../../Downloads/loop.wav", type: 1), ref(container: "MxPatchRef", abs: t.sub("Downloads/dev.amxd")),
        ]
        let deps = SampleScan.of(info, setDir: setDir, env: e)
        XCTAssertEqual(deps.count, 2, "one sample, one (missing) device; the preset is only provenance")
        XCTAssertEqual(deps[0].refIndexes, [0, 1, 4])
        XCTAssertEqual(deps[0].name, "loop.wav")
        XCTAssertTrue(deps[1].isDevice)
        XCTAssertEqual(SampleScan.of(nil, setDir: setDir, env: e).count, 0)
    }

    func testAFolderDeviceIsSizedByItsContents() {
        let t = makeTemp("scan")
        let e = env(t)
        let bundle = t.sub("Downloads/synth.adg")
        SampleFixtures.put(Data(count: 10), at: bundle + "/a")
        SampleFixtures.put(Data(count: 20), at: bundle + "/deep/b")
        var info = AlsInfo()
        info.files = [ref(container: "MxPatchRef", abs: bundle)]
        XCTAssertEqual(SampleScan.of(info, setDir: t.sub("Music/X Project"), env: e).first?.size, 30)
    }

    func testInSomeProjectLooksFourLevelsUp() {
        XCTAssertTrue(SampleScan.inSomeProject("/m/A Project/Samples/x.wav"))
        XCTAssertTrue(SampleScan.inSomeProject("/m/A Project/Samples/Imported/Deep/x.wav"))
        XCTAssertTrue(SampleScan.inSomeProject("/m/A Project/a/b/c/x.wav"))
        XCTAssertFalse(SampleScan.inSomeProject("/m/A Project/a/b/c/d/x.wav"))
        XCTAssertFalse(SampleScan.inSomeProject("/m/Music/x.wav"))
    }
}
