import XCTest
@testable import AliveCore

/// `PluginInventory.load` against a fake machine: system and user plug-in folders, Live's
/// preferences, custom folders from the settings.
final class PluginInventoryLoadTests: XCTestCase {
    private struct Machine {
        let t: TempDir
        var locations: PluginLocations {
            PluginLocations(home: t.sub("home"), systemPlugIns: t.sub("system"), livePreferences: t.sub("home/Library/Preferences/Ableton"))
        }
    }

    private func machine() -> Machine { Machine(t: makeTemp("machine")) }

    private func au(_ m: Machine, _ rel: String, name: String, type: String = "aufx", sub: String, manufacturer: String) {
        PluginFixtures.component(m.t, rel, components: [PluginFixtures.audioComponent(name: name, type: type, sub: sub, manufacturer: manufacturer)])
    }

    // MARK: folders

    func testBundlesOfAllFormatsAreFoundInSystemAndUserFolders() {
        let m = machine()
        au(m, "system/Components/Reverb.component", name: "Acme: Reverb", sub: "rvrb", manufacturer: "acme")
        au(m, "home/Library/Audio/Plug-Ins/Components/Mine.component", name: "Me: Mine", sub: "mine", manufacturer: "meee")
        PluginFixtures.vst3(m.t, "system/VST3/Vendor Folder/Deep/Synth.vst3",
                            moduleInfo: PluginFixtures.moduleInfo(cid: "00000000000000000000000000000001", name: "Synth", vendor: "V", sub: ["Instrument", "Synth"]))
        PluginFixtures.vst3(m.t, "home/Library/Audio/Plug-Ins/VST3/Plain.vst3")
        m.t.write("system/VST/Old.vst/Contents/Info.plist", PluginFixtures.plist(["CFBundleName": "Old"]))
        m.t.write("system/VST/.DS_Store")
        m.t.write("system/VST/readme.txt")

        let inv = PluginInventory.load(settings: Settings(), locations: m.locations)
        XCTAssertTrue(inv.isAvailable)
        XCTAssertNil(inv.error)
        XCTAssertEqual(Set(inv.all.map(\.uid)), [
            "au:aufx:rvrb:acme", "au:aufx:mine:meee", "vst3:00000000-0000-0000-0000-000000000001",
            "file:vst3:plain", "file:vst2:old",
        ])
        XCTAssertEqual(inv.all.filter { $0.format == "AU" }.count, 2)
        XCTAssertEqual(inv.byUid("vst3:00000000-0000-0000-0000-000000000001")?.category, "Instrument|Synth")
        XCTAssertTrue(inv.sources.contains { $0.hasPrefix("Audio Units · 2") })
        XCTAssertEqual(inv.describe().hasPrefix("5 plugins"), true)
    }

    func testBundlesAreNotEnteredAndDuplicatesCollapse() {
        let m = machine()
        // A .vst3 holding another .vst3 (a real binary bundle inside the wrapper) is one plugin.
        PluginFixtures.vst3(m.t, "system/VST3/Outer.vst3")
        m.t.mkdir("system/VST3/Outer.vst3/Contents/Inner.vst3")
        // The same AU in the system and the user folder counts once (system first).
        au(m, "system/Components/Twin.component", name: "A: Twin", sub: "twin", manufacturer: "aaaa")
        au(m, "home/Library/Audio/Plug-Ins/Components/Twin.component", name: "A: Twin", sub: "twin", manufacturer: "aaaa")
        let inv = PluginInventory.load(settings: Settings(), locations: m.locations)
        XCTAssertEqual(inv.all.count, 2)
        XCTAssertEqual(inv.byUid("au:aufx:twin:aaaa")?.path, m.t.sub("system/Components/Twin.component"))
    }

    func testSymlinkedVendorFolderIsWalkedOnceAndLoopsAreSafe() throws {
        let m = machine()
        m.t.mkdir("elsewhere")
        PluginFixtures.vst3(m.t, "elsewhere/Linked.vst3")
        m.t.mkdir("system/VST3")
        try FileManager.default.createSymbolicLink(atPath: m.t.sub("system/VST3/Vendor"), withDestinationPath: m.t.sub("elsewhere"))
        try FileManager.default.createSymbolicLink(atPath: m.t.sub("elsewhere/loop"), withDestinationPath: m.t.sub("system/VST3"))
        let inv = PluginInventory.load(settings: Settings(), locations: m.locations)
        XCTAssertEqual(inv.all.map(\.name), ["Linked"])
    }

    func testCustomFoldersAndTheVst3SystemSwitch() {
        let m = machine()
        PluginFixtures.vst3(m.t, "system/VST3/InSystem.vst3")
        PluginFixtures.vst3(m.t, "custom3/Mine.vst3")
        PluginFixtures.vst3(m.t, "custom3b/Also.vst3")
        m.t.write("custom2/Legacy.vst/Contents/Info.plist", PluginFixtures.plist([:]))
        var s = Settings()
        s.vst3SystemOn = false
        s.vst3CustomOn = true
        s.vst3CustomPath = m.t.sub("custom3") + ";" + m.t.sub("custom3b") + ";  "
        s.vst2CustomOn = true
        s.vst2CustomPath = m.t.sub("custom2")
        let inv = PluginInventory.load(settings: s, locations: m.locations)
        XCTAssertEqual(Set(inv.all.map(\.name)), ["Mine", "Also", "Legacy"])
        // Switched off: the paths are ignored.
        s.vst3CustomOn = false; s.vst2CustomOn = false
        XCTAssertTrue(PluginInventory.load(settings: s, locations: m.locations).all.isEmpty)
        XCTAssertEqual(PluginInventory.customFolders(" ~/x ;\n/y;;"), [NSHomeDirectory() + "/x", "/y"])
    }

    // MARK: Live's records

    private func writeLog(_ m: Machine, version: String, plugins: [(name: String, cid: String, bundle: String)], age: TimeInterval = 0) {
        var text = ""
        for p in plugins {
            text += """
            2026-01-01T00:00:00.1: info: VST3: found: \(p.name)
               vendor: Live Vendor
               device-class-id: device:vst3:audiofx:\(p.cid)?n=\(p.name)
               version: 4.0
               subCategories: Fx|Dynamics
               path: "\(p.bundle)"

            """
        }
        let rel = "home/Library/Preferences/Ableton/\(version)/PluginScanner.txt"
        m.t.write(rel, text)
        m.t.setModified(m.t.sub(rel), Date().addingTimeInterval(-age))
    }

    func testLiveLogGivesVst3IdsOfBundlesWithoutModuleInfo() {
        let m = machine()
        let bundle = PluginFixtures.vst3(m.t, "system/VST3/FabFilter Pro-L 2.vst3")
        writeLog(m, version: "Live 11.3.35", plugins: [("Pro-L 2", "aaaaaaaa-1111-2222-3333-444444444444", bundle)])
        let inv = PluginInventory.load(settings: Settings(), locations: m.locations)
        // One plugin, with Live's real id, name, vendor, category — not the file-name guess.
        XCTAssertEqual(inv.all.count, 1)
        XCTAssertEqual(inv.all[0].uid, "vst3:aaaaaaaa-1111-2222-3333-444444444444")
        XCTAssertEqual(inv.all[0].vendor, "Live Vendor")
        XCTAssertEqual(inv.all[0].category, "Fx|Dynamics")
        XCTAssertEqual(inv.liveVersion, "Live 11.3.35")
        XCTAssertTrue(inv.sourcePath.hasSuffix("PluginScanner.txt"))
        // The file name is an alias: a set that says "FabFilter Pro-L 2" finds it too.
        XCTAssertEqual(inv.match(uid: "", name: "FabFilter Pro-L 2").kind, .otherFormat)
        XCTAssertEqual(inv.match(uid: "vst3:aaaaaaaa-1111-2222-3333-444444444444", name: "?").kind, .exact)
    }

    func testFoldersOnlyIgnoresLiveAndPluginSourceNarrowsIt() {
        let m = machine()
        let bundle = PluginFixtures.vst3(m.t, "system/VST3/Thing.vst3")
        let other = PluginFixtures.vst3(m.t, "system/VST3/Other.vst3")
        writeLog(m, version: "Live 11.3.35", plugins: [("Thing", "aaaaaaaa-1111-2222-3333-444444444444", bundle)], age: 0)
        writeLog(m, version: "Live 11.2.7", plugins: [("Other", "bbbbbbbb-1111-2222-3333-444444444444", other)], age: 1000)

        var s = Settings()
        s.pluginsFromFolders = true
        XCTAssertEqual(Set(PluginInventory.load(settings: s, locations: m.locations).all.map(\.uid)), ["file:vst3:thing", "file:vst3:other"])

        s.pluginsFromFolders = false
        let both = PluginInventory.load(settings: s, locations: m.locations)
        XCTAssertEqual(Set(both.all.map(\.uid)), ["vst3:aaaaaaaa-1111-2222-3333-444444444444", "vst3:bbbbbbbb-1111-2222-3333-444444444444"])
        XCTAssertEqual(both.liveVersion, "Live 11.3.35")               // the newest install is the principal one

        s.pluginSource = "live 11.2.7"                                  // case-insensitive, like upstream
        let only = PluginInventory.load(settings: s, locations: m.locations)
        XCTAssertEqual(only.liveVersion, "Live 11.2.7")
        XCTAssertEqual(Set(only.all.map(\.uid)), ["vst3:bbbbbbbb-1111-2222-3333-444444444444", "file:vst3:thing"])
        XCTAssertEqual(PluginInventory.installs(locations: m.locations), ["Live 11.3.35", "Live 11.2.7"])
    }

    func testOlderInstallsAreResurrectedOnlyWhileTheirFileExists() {
        let m = machine()
        let kept = PluginFixtures.vst3(m.t, "system/VST3/Kept.vst3")
        writeLog(m, version: "Live 11.3.35", plugins: [], age: 0)
        writeLog(m, version: "Live 11.2.7", plugins: [
            ("Kept", "cccccccc-1111-2222-3333-444444444444", kept),
            ("Deleted", "dddddddd-1111-2222-3333-444444444444", m.t.sub("system/VST3/Deleted.vst3")),
        ], age: 1000)
        let inv = PluginInventory.load(settings: Settings(), locations: m.locations)
        XCTAssertEqual(inv.all.map(\.name), ["Kept"])
    }

    // MARK: nothing there

    func testNothingFoundIsUnavailableNotAnErrorPerPlugin() {
        let m = machine()
        m.t.mkdir("system")
        let inv = PluginInventory.load(settings: Settings(), locations: m.locations)
        XCTAssertTrue(inv.isEmpty)
        XCTAssertFalse(inv.isAvailable)
        XCTAssertNotNil(inv.error)
        XCTAssertEqual(inv.describe(), inv.error)
        XCTAssertEqual(inv.match(uid: "vst3:x", name: "Anything").kind, .unknown)
    }

    func testUnreadableAndBrokenBundlesDoNotStopTheScan() {
        let m = machine()
        m.t.write("system/Components/Broken.component/Contents/Info.plist", "<<<")
        m.t.write("system/VST3/Empty.vst3", "a flat file")                 // a plain-file .vst3
        au(m, "system/Components/Fine.component", name: "A: Fine", sub: "fine", manufacturer: "aaaa")
        let inv = PluginInventory.load(settings: Settings(), locations: m.locations)
        XCTAssertEqual(Set(inv.all.map(\.name)), ["Broken", "Empty", "Fine"])
    }

    func testManyBundlesScanQuickly() {
        let m = machine()
        for i in 0..<400 {
            au(m, "system/Components/P\(i).component", name: "V: P\(i)", sub: String(format: "p%03d", i), manufacturer: "vend")
        }
        let started = Date()
        let inv = PluginInventory.load(settings: Settings(), locations: m.locations)
        XCTAssertEqual(inv.all.count, 400)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
}
