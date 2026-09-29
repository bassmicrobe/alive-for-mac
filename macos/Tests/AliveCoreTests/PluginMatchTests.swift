import XCTest
@testable import AliveCore

/// `PluginInventory.match`: identifier first, then name; unknown when nothing could be read.
final class PluginMatchTests: XCTestCase {
    private func plugin(_ uid: String, _ name: String, vendor: String = "", kind: PluginKind = .vst3, aliases: [String] = []) -> InstalledPlugin {
        var p = InstalledPlugin()
        p.uid = uid; p.name = name; p.vendor = vendor; p.kind = kind; p.aliases = aliases
        return p
    }

    func testAudioUnitFourCCIsAnExactMatchCaseInsensitively() {
        var inv = PluginInventory()
        inv.add(plugin("au:aumu:Falc:UVI ", "Falcon", vendor: "UVI", kind: .audioUnit))
        XCTAssertEqual(inv.match(uid: "au:aumu:Falc:UVI ", name: "whatever").kind, .exact)
        XCTAssertEqual(inv.match(uid: "AU:AUMU:FALC:UVI ", name: "whatever").kind, .exact)
        XCTAssertEqual(inv.match(uid: "au:aumu:Falc:UVI ", name: "").plugin?.name, "Falcon")
    }

    func testVst3UidIsExactAndTheNameFallbackIsOtherFormat() {
        var inv = PluginInventory()
        inv.add(plugin("vst3:ed57bd72-5c60-467e-a64d-d2f400758b6f", "Pro-Q 4", vendor: "FabFilter"))
        XCTAssertEqual(inv.match(uid: "vst3:ED57BD72-5C60-467E-A64D-D2F400758B6F", name: "x").kind, .exact)
        // A set that stored the VST2 build: another id, the same plugin.
        XCTAssertEqual(inv.match(uid: "vst2:1234", name: "Pro-Q 4").kind, .otherFormat)
        // "FabFilter Pro-Q 4" in the set, "Pro-Q 4" by FabFilter on the machine.
        XCTAssertEqual(inv.match(uid: "vst2:1234", name: "FabFilter Pro-Q 4").kind, .otherFormat)
        XCTAssertEqual(inv.match(uid: "vst3:0000", name: "Nothing like it").kind, .missing)
        XCTAssertNil(inv.match(uid: "", name: "Nothing").plugin)
    }

    func testNameMatchIgnoresPunctuationCaseAndBitnessSuffixes() {
        var inv = PluginInventory()
        inv.add(plugin("vst3:aaa", "Serum", kind: .vst3))
        for name in ["Serum_x64", "serum (64 bit)", "SERUM", "Serum-VST3"] {
            XCTAssertEqual(inv.match(uid: "vst2:1", name: name).kind, .otherFormat, name)
        }
    }

    func testAFileIdentifiedBundleCountsAsTheSamePluginInTheSameFormat() {
        var inv = PluginInventory()
        inv.add(plugin("file:vst3:serum2", "Serum 2", kind: .vst3))
        inv.add(plugin("file:vst2:serum2", "Serum 2", kind: .vst2))
        inv.add(plugin("file:au:massive", "Massive", kind: .audioUnit))
        XCTAssertEqual(inv.match(uid: "vst3:ed57bd72-5c60-467e-a64d-d2f400758b6f", name: "Serum 2").kind, .exact)
        XCTAssertEqual(inv.match(uid: "vst3:ed57bd72-5c60-467e-a64d-d2f400758b6f", name: "Serum 2").plugin?.kind, .vst3)
        XCTAssertEqual(inv.match(uid: "vst2:2017543218", name: "Serum 2").plugin?.kind, .vst2)
        XCTAssertEqual(inv.match(uid: "vst2:2017543218", name: "Serum 2").kind, .exact)
        // Another format than any installed one for that name.
        XCTAssertEqual(inv.match(uid: "au:aumu:abcd:efgh", name: "Serum 2").kind, .otherFormat)
        XCTAssertEqual(inv.match(uid: "au:aumu:abcd:efgh", name: "Massive").kind, .exact)
    }

    func testARealUidElsewhereDoesNotPromoteAFileIdentifiedTwin() {
        var inv = PluginInventory()
        inv.add(plugin("vst3:real", "Thing", kind: .vst3))
        XCTAssertEqual(inv.match(uid: "vst3:other", name: "Thing").kind, .otherFormat)
    }

    func testAliasesAndVendorPlusNameAreIndexed() {
        var inv = PluginInventory()
        inv.add(plugin("vst3:x", "Pro-L 2", vendor: "FabFilter", aliases: ["FabFilter Pro-L 2 (Stereo)"]))
        XCTAssertNotNil(inv.byName("FabFilter Pro-L 2"))
        XCTAssertNotNil(inv.byName("fabfilterprol2stereo"))
        XCTAssertNil(inv.byName("L"))                                      // too short to index
    }

    func testUnavailableInventoryNeverSaysMissing() {
        let inv = PluginInventory()
        XCTAssertFalse(inv.isAvailable)
        let m = inv.match(uid: "vst3:x", name: "Serum")
        XCTAssertEqual(m.kind, .unknown)
        XCTAssertTrue(m.found)                                             // "not missing"
        XCTAssertNil(m.plugin)
    }

    func testAddContentsOfKeepsOnePerIdentifierAndPrefersAFileThatExists() {
        var inv = PluginInventory()
        var gone = plugin("vst3:a", "A"); gone.fileMissing = true
        var back = plugin("vst3:a", "A"); back.path = "/there"
        inv.add(contentsOf: [gone, plugin("vst3:b", "B"), back, plugin("VST3:B", "B again")])
        XCTAssertEqual(inv.all.map(\.uid), ["vst3:a", "vst3:b"])
        XCTAssertEqual(inv.all[0].path, "/there")
        XCTAssertFalse(inv.all[0].fileMissing)
        XCTAssertEqual(inv.all[1].name, "B")
        // Records without an id are kept as they are.
        inv.add(contentsOf: [plugin("", "No id 1"), plugin("", "No id 2")])
        XCTAssertEqual(inv.all.count, 4)
    }
}
