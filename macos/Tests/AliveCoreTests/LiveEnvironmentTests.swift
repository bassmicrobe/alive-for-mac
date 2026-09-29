import XCTest
@testable import AliveCore

final class LiveVersionTests: XCTestCase {
    private func v(_ s: String) -> LiveVersion { LiveVersion(folderName: s)! }

    func testParsing() {
        XCTAssertEqual(v("Live 12.0b20").numbers, [12, 0])
        XCTAssertEqual(v("Live 12.0b20").beta, 20)
        XCTAssertEqual(v("Live 11.3.20b1").numbers, [11, 3, 20])
        XCTAssertNil(v("Live 11.3.35").beta)
        XCTAssertEqual(v("Live 11.3.35").description, "11.3.35")
        XCTAssertEqual(v("Live 12.0b20").description, "12.0b20")
        XCTAssertEqual(LiveVersion("Ableton Live 11.3.35 Suite")?.numbers, [11, 3, 35])
        XCTAssertNil(LiveVersion(folderName: "Live"))
        XCTAssertNil(LiveVersion(folderName: "Other 1.0"))
        XCTAssertNil(LiveVersion("no digits"))
        XCTAssertTrue(v("Live 12.0b20").isBeta)
    }

    func testOrderingWithBetas() {
        let names = ["Live 10.1.41", "Live 10.1.42", "Live 11.0.12", "Live 11.1b10", "Live 11.1b7", "Live 11.1",
                     "Live 11.1.1", "Live 11.2", "Live 11.3.2", "Live 11.3.20b1", "Live 11.3.20", "Live 11.3.3",
                     "Live 11.3.35", "Live 12.0b20"]
        let sorted = names.shuffled().sorted { v($0) < v($1) }
        XCTAssertEqual(sorted, ["Live 10.1.41", "Live 10.1.42", "Live 11.0.12", "Live 11.1b7", "Live 11.1b10",
                                "Live 11.1", "Live 11.1.1", "Live 11.2", "Live 11.3.2", "Live 11.3.3",
                                "Live 11.3.20b1", "Live 11.3.20", "Live 11.3.35", "Live 12.0b20"])
        XCTAssertTrue(v("Live 11.3.20") > v("Live 11.3.20b1"))          // a release outranks its betas
        XCTAssertTrue(v("Live 12.0b20") > v("Live 11.3.35"))
    }
}

final class LiveEnvironmentTests: XCTestCase {
    private func libraryCfg(userLib: String? = nil, folders: [(String, String)] = [], slices: [(String, String)] = [],
                            packs: String = "") -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Ableton><ContentLibrary>"
        if let userLib {
            s += "<UserLibrary><LibraryProject Id=\"0\"><ProjectLocation/><ProjectName Value=\"User Library\"/>"
                + "<ProjectPath Value=\"\(userLib)\"/></LibraryProject></UserLibrary>"
        }
        s += "<SliceInfoList>" + slices.map { "<LibrarySliceInfo Path=\"\($0.1)\" DisplayName=\"\($0.0)\" UniqueId=\"1\"/>" }.joined() + "</SliceInfoList>"
        s += "<UserFolderInfoList>" + folders.map { "<UserFolderInfo Id=\"1\" Path=\"\($0.1)\" DisplayName=\"\($0.0)\"/>" }.joined() + "</UserFolderInfoList>"
        s += "<PreferredFactoryPacksInstallationPath Value=\"\(packs)\"/></ContentLibrary></Ableton>"
        return s
    }

    private func fakeHome(_ t: TempDir) -> (home: String, apps: String) {
        let home = t.mkdir("home")
        let prefs = home + "/Library/Preferences/Ableton"
        for n in ["Live 11.3.35", "Live 12.0b20", "Live 11.3.20b1", "Live 11.3.20", "Live 10.1.41"] {
            t.mkdir("home/Library/Preferences/Ableton/\(n)")
        }
        t.mkdir("home/Library/Preferences/Ableton/Not Live")
        t.write("home/Library/Preferences/Ableton/Live file.txt")
        t.mkdir("home/Music/Ableton/User Library")
        t.mkdir("home/Packs/Core")
        t.mkdir("home/Samples")
        t.mkdir("home/Factory Packs")
        t.write("home/Library/Preferences/Ableton/Live 11.3.35/Library.cfg",
                libraryCfg(userLib: home + "/Music/Ableton",
                           folders: [("old name", home + "/Samples"), ("gone", home + "/Nowhere")],
                           slices: [("Drum Essentials", home + "/Packs/Core")]))
        t.write("home/Library/Preferences/Ableton/Live 12.0b20/Library.cfg",
                libraryCfg(folders: [("Samples", home + "/Samples"), ("", home + "/Packs")], packs: home + "/Factory Packs"))
        t.write("home/Library/Preferences/Ableton/Live 10.1.41/Library.cfg", "<broken")
        _ = prefs

        let apps = t.mkdir("Applications")
        t.mkdir("Applications/Ableton Live 11 Suite.app/Contents/App-Resources/Builtin")
        t.write("Applications/Ableton Live 11 Suite.app/Contents/Info.plist",
                "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleShortVersionString</key><string>11.3.35</string></dict></plist>")
        t.mkdir("Applications/Ableton Live 12 Beta.app/Contents/App-Resources")
        t.write("Applications/Ableton Live 12 Beta.app/Contents/Info.plist",
                "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleShortVersionString</key><string>12.0b20</string></dict></plist>")
        t.mkdir("Applications/Ableton Live 9 Lite.app/Contents/App-Resources")     // no plist: name fallback
        t.mkdir("Applications/Ableton Live Broken.app")                             // no resources: skipped
        t.mkdir("Applications/Other.app/Contents/App-Resources")
        return (home, apps)
    }

    func testPrefsFoldersSortedOldestToNewest() {
        let t = makeTemp()
        let f = fakeHome(t)
        let names = LiveEnvironment.findPrefsFolders(home: f.home).map { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(names, ["Live 10.1.41", "Live 11.3.20b1", "Live 11.3.20", "Live 11.3.35", "Live 12.0b20"])
    }

    func testDetectFromFakeHome() {
        let t = makeTemp()
        let f = fakeHome(t)
        let env = LiveEnvironment.detect(home: f.home, applicationsDirs: [f.apps])

        XCTAssertEqual((env.newestPrefsFolder! as NSString).lastPathComponent, "Live 12.0b20")
        XCTAssertEqual(env.installs.map { ($0.appPath as NSString).lastPathComponent },
                       ["Ableton Live 12 Beta.app", "Ableton Live 11 Suite.app", "Ableton Live 9 Lite.app"])
        XCTAssertTrue(env.installs[0].isBeta)
        XCTAssertEqual(env.installDir, f.apps + "/Ableton Live 12 Beta.app")
        XCTAssertEqual(env.builtin, env.installDir + "/Contents/App-Resources/Builtin")
        XCTAssertEqual(env.coreLibrary, env.installDir + "/Contents/App-Resources/Core Library")

        // Library.cfg: user library from ProjectPath + ProjectName, packs, places.
        XCTAssertEqual(env.userLibrary, f.home + "/Music/Ableton/User Library")
        XCTAssertEqual(env.packRoot(named: "drum essentials"), f.home + "/Packs/Core")     // case-insensitive
        XCTAssertEqual(env.packRoot(named: "Core Library"), env.coreLibrary)
        XCTAssertEqual(env.packsFolder, f.home + "/Factory Packs")
        XCTAssertEqual(env.places.map(\.name), ["Samples", "Packs"])                        // newest Live names it; gone skipped
        XCTAssertEqual(env.places[1].path, f.home + "/Packs")
    }

    func testDefaultsWhenNothingIsInstalled() {
        let t = makeTemp()
        let env = LiveEnvironment.detect(home: t.path, applicationsDirs: [t.path + "/none"])
        XCTAssertEqual(env.installDir, "")
        XCTAssertEqual(env.builtin, "")
        XCTAssertEqual(env.userLibrary, t.path + "/Music/Ableton/User Library")
        XCTAssertNil(env.newestPrefsFolder)
        XCTAssertTrue(env.prefsFolders.isEmpty)
        XCTAssertNil(env.packRoot(named: "x"))
    }

    func testAddPlaceKeepsLastName() {
        var e = LiveEnvironment()
        e.addPlace("A", "/x/y/")
        e.addPlace("B", "/x/y")
        XCTAssertEqual(e.places, [LivePlace(name: "B", path: "/x/y/")])
    }

    func testSnapshotMentionsInstall() {
        let t = makeTemp()
        let f = fakeHome(t)
        let env = LiveEnvironment.detect(home: f.home, applicationsDirs: [f.apps])
        let text = Diag.snapshot(env: env)
        XCTAssertTrue(text.contains("Ableton Live 12 Beta.app"))
        XCTAssertTrue(text.contains("macOS"))
    }

    /// This machine's real preferences, when Live is installed (skipped elsewhere).
    func testRealMachineSanity() throws {
        let prefs = NSHomeDirectory() + "/Library/Preferences/Ableton"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: prefs), "no Live preferences here")
        let env = LiveEnvironment.detect()
        XCTAssertFalse(env.prefsFolders.isEmpty)
        let sorted = env.prefsFolders.compactMap { LiveVersion(folderName: ($0 as NSString).lastPathComponent) }
        XCTAssertEqual(sorted, sorted.sorted())
    }
}
