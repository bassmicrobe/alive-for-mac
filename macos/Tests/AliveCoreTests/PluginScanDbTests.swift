import XCTest
@testable import AliveCore

final class PluginScanDbTests: XCTestCase {
    private func lines(_ s: String) -> [String] { s.components(separatedBy: "\n") }

    // MARK: PluginScanDb.txt

    func testParseDbReadsModulesAndPlugins() {
        let t = makeTemp("scandb")
        let present = t.mkdir("VST3/Serum2.vst3")                 // a bundle folder, not a file
        let db = """
        Logging plugins information about plugin modules start
        ModuleId,Path,Type,Cat,State
        1,"\(present)",3,1,ok,"x"
        2,"/nowhere/Gone.vst3",3,1,ok,"x"
        3,"/x/NotAPlugin.vst3",3,1,not-a-plugin,"x"
        Logging plugins information about plugin modules end
        Logging plugins information about all plugins start
        PluginId,ModuleId,DeviceId,Name,Vendor,Version,a,b,c,Category,Enabled
        10,1,"device:vst3:instr:ed57bd72-5c60-467e-a64d-d2f400758b6f?n=Serum%202",Serum 2,Xfer Records,2.0.1,,,,Instrument|Synth,1
        11,2,"device:vst:audiofx:1234567?n=Gone",Gone,Someone,1.0,,,,,0
        12,3,"device:vst3:audiofx:aaaa",Skipped,Nobody,1,,,,,1
        Logging plugins information about all plugins end
        """
        let list = PluginScanDb.parseDb(lines(db), paths: PathExistsCache())
        XCTAssertEqual(list.map(\.name), ["Serum 2", "Gone"])
        XCTAssertEqual(list[0].uid, "vst3:ed57bd72-5c60-467e-a64d-d2f400758b6f")
        XCTAssertEqual(list[0].vendor, "Xfer Records")
        XCTAssertEqual(list[0].version, "2.0.1")
        XCTAssertEqual(list[0].category, "Instrument|Synth")
        XCTAssertTrue(list[0].enabled)
        XCTAssertFalse(list[0].fileMissing)
        XCTAssertEqual(list[1].uid, "vst2:1234567")
        XCTAssertEqual(list[1].kind, .vst2)
        XCTAssertTrue(list[1].fileMissing)
        XCTAssertFalse(list[1].enabled)
        XCTAssertEqual(list[1].category, "Fx")                    // from the device class segment
    }

    func testParseDbIgnoresRowsOutsideTablesAndShortRows() {
        let db = "stray line\n1,2,3\nLogging plugins information about all plugins start\nshort,row\n"
        XCTAssertTrue(PluginScanDb.parseDb(lines(db), paths: PathExistsCache()).isEmpty)
    }

    // MARK: PluginScanner.txt

    private func logBlock(_ name: String, kind: String = "VST3", vendor: String = "V", device: String,
                          path: String, sub: String = "Fx|Filter", version: String = "1.0") -> String {
        """
        2026-03-28T22:45:33.478735: info: \(kind): found: \(name)
           vendor: \(vendor)
           url:
           device-class-id: \(device)
           version: \(version)
           subCategories: \(sub)
           path: "\(path)"
           fp: a24400:69174b9c
        """
    }

    func testScannerLogKeepsLastRecordAndOnlyFilesThatExist() {
        let t = makeTemp("scanlog")
        let a = t.mkdir("VST3/A.vst3")
        let vst2 = t.mkdir("VST/B.vst")
        let log = [
            "2026-03-28T22:45:20.1: info: Started: PluginScanner",
            logBlock("Alpha", vendor: "Old Vendor", device: "device:vst3:audiofx:11111111-2222-3333-4444-555555555555?n=Alpha", path: a, version: "1.0"),
            "2026-03-28T22:45:33.9: info: VST3: check plugin at path: \"x\"",
            logBlock("Alpha", vendor: "New Vendor", device: "device:vst3:audiofx:11111111-2222-3333-4444-555555555555?n=Alpha", path: a, version: "2.0"),
            logBlock("Beta", kind: "VST2", device: "device:vst:instr:987654?n=Beta", path: vst2, sub: ""),
            logBlock("Removed", device: "device:vst3:audiofx:99999999-2222-3333-4444-555555555555", path: "/nowhere/R.vst3"),
            "2026-03-28T22:45:34.0: error: Failed to load plugin",
            "2026-03-28T22:45:34.1: info: VST3: not a plugin",
        ].joined(separator: "\n")
        let list = PluginScanDb.parseScannerLog(lines(log), known: [], paths: PathExistsCache())
        XCTAssertEqual(list.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(list[0].vendor, "New Vendor")              // the last record of a plugin wins
        XCTAssertEqual(list[0].version, "2.0")
        XCTAssertEqual(list[0].uid, "vst3:11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(list[0].category, "Fx|Filter")
        XCTAssertEqual(list[0].path, a)
        XCTAssertEqual(list[1].uid, "vst2:987654")
        XCTAssertEqual(list[1].category, "Instrument")            // no subCategories: from the device id
    }

    func testScannerLogSkipsWhatTheDatabaseKnows() {
        let t = makeTemp("scanlog-known")
        let a = t.mkdir("A.vst3")
        let log = logBlock("Alpha", device: "device:vst3:audiofx:11111111-2222-3333-4444-555555555555", path: a)
        let list = PluginScanDb.parseScannerLog(lines(log), known: ["vst3:11111111-2222-3333-4444-555555555555"], paths: PathExistsCache())
        XCTAssertTrue(list.isEmpty)
    }

    func testScannerLogBlockWithoutDeviceIdIsDropped() {
        let t = makeTemp("scanlog-nodev")
        let log = "x: info: VST3: found: Odd\n   vendor: V\n   path: \"\(t.mkdir("Odd.vst3"))\"\nnext line"
        XCTAssertTrue(PluginScanDb.parseScannerLog(lines(log), known: [], paths: PathExistsCache()).isEmpty)
    }

    // MARK: identifiers and folders

    func testUidOfDevice() {
        XCTAssertEqual(PluginScanDb.uid(ofDevice: "device:vst3:audiofx:AB-CD?n=X", kind: .vst3), "vst3:ab-cd")
        XCTAssertEqual(PluginScanDb.uid(ofDevice: "device:vst:instr:2017543218?n=Addictive%20Drums%202", kind: .vst2), "vst2:2017543218")
        XCTAssertEqual(PluginScanDb.uid(ofDevice: "device:au:audiofx:aufx:rmx1:pion", kind: .audioUnit), "au:aufx:rmx1:pion")
        XCTAssertEqual(PluginScanDb.uid(ofDevice: "", kind: .vst3), "")
        XCTAssertEqual(PluginScanDb.uid(ofDevice: "nocolon", kind: .vst3), "")
        XCTAssertEqual(PluginScanDb.uid(ofDevice: "device:vst3:audiofx:", kind: .vst3), "")
    }

    func testSplitCsvStripsQuotesAndKeepsCommasInside() {
        XCTAssertEqual(PluginScanDb.splitCsv(#"1,"C:\a,b\x.vst3",3,,ok"#), ["1", #"C:\a,b\x.vst3"#, "3", "", "ok"])
    }

    func testVersionFoldersNewestWrittenFirstAndBothLayouts() throws {
        let t = makeTemp("versions")
        t.write("Ableton/Live 11.3.10/PluginScanner.txt")                 // Mac layout
        t.write("Ableton/Live 12.0/Preferences/PluginScanDb.txt")         // Windows layout
        t.mkdir("Ableton/Live 9.0/Preferences")                           // a Live install with no plugin files
        t.mkdir("Ableton/Other")                                          // not Live
        t.write("Ableton/.hidden/PluginScanner.txt")
        t.setModified(t.sub("Ableton/Live 11.3.10/PluginScanner.txt"), Date(timeIntervalSince1970: 2_000_000_000))
        t.setModified(t.sub("Ableton/Live 12.0/Preferences/PluginScanDb.txt"), Date(timeIntervalSince1970: 1_000_000_000))
        let names = PluginScanDb.versionFolders(root: t.sub("Ableton")).map { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(names, ["Live 11.3.10", "Live 12.0", "Live 9.0"])
        XCTAssertTrue(PluginScanDb.versionFolders(root: t.sub("nothing")).isEmpty)
    }

    func testVersionFoldersWithoutTheLiveMaskLookAtEverySubfolder() {
        let t = makeTemp("versions-mask")
        t.write("Ableton/Beta Build/PluginScanner.txt")
        let names = PluginScanDb.versionFolders(root: t.sub("Ableton")).map { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(names, ["Beta Build"])
    }

    func testReadCombinesDatabaseAndLogFromOneInstall() {
        let t = makeTemp("read-install")
        let a = t.mkdir("VST3/A.vst3"), b = t.mkdir("VST3/B.vst3")
        let db = """
        Logging plugins information about plugin modules start
        1,"\(a)",3,1,ok,"x"
        Logging plugins information about plugin modules end
        Logging plugins information about all plugins start
        10,1,"device:vst3:audiofx:aaaaaaaa-0000-0000-0000-000000000001",A,V,1,,,,Fx,1
        Logging plugins information about all plugins end
        """
        t.write("Live 11/Preferences/PluginScanDb.txt", db)
        t.write("Live 11/Preferences/PluginScanner.txt",
                logBlock("A", device: "device:vst3:audiofx:aaaaaaaa-0000-0000-0000-000000000001", path: a) + "\n"
                + logBlock("B", device: "device:vst3:audiofx:bbbbbbbb-0000-0000-0000-000000000002", path: b))
        let rec = PluginScanDb.read(versionDir: t.sub("Live 11"), paths: PathExistsCache())
        XCTAssertEqual(rec.plugins.map(\.name), ["A", "B"])         // A from the database, B only in the log
        XCTAssertTrue(rec.sourcePath.hasSuffix("PluginScanDb.txt"))
        XCTAssertGreaterThan(rec.scanned, .distantPast)
    }
}
