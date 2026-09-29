import XCTest
@testable import AliveCore

/// Fake plugin bundles written to a temp folder: plist / moduleinfo fixtures, broken files, the
/// legacy resource-fork registration.
enum PluginFixtures {
    static func plist(_ dict: [String: Any]) -> String {
        let data = try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        return String(decoding: data, as: UTF8.self)
    }

    /// `<root>/<Name>.component` with an AudioComponents plist.
    @discardableResult
    static func component(_ t: TempDir, _ rel: String, components: [[String: Any]], version: String? = "1.2.3") -> String {
        var info: [String: Any] = ["CFBundleName": "X", "AudioComponents": components]
        if let version { info["CFBundleShortVersionString"] = version }
        t.write(rel + "/Contents/Info.plist", plist(info))
        return t.sub(rel)
    }

    static func audioComponent(name: String, type: String, sub: String, manufacturer: String,
                               version: Int = 65_793) -> [String: Any] {
        ["name": name, "type": type, "subtype": sub, "manufacturer": manufacturer, "version": version]
    }

    @discardableResult
    static func vst3(_ t: TempDir, _ rel: String, moduleInfo: String? = nil, plist info: [String: Any]? = nil) -> String {
        if let moduleInfo { t.write(rel + "/Contents/Resources/moduleinfo.json", moduleInfo) }
        t.write(rel + "/Contents/Info.plist", plist(info ?? ["CFBundleName": "Bundle", "CFBundleShortVersionString": "9.9"]))
        return t.sub(rel)
    }

    static func moduleInfo(cid: String, name: String, vendor: String, sub: [String] = ["Fx", "EQ"],
                           category: String = "Audio Module Class") -> String {
        """
        {"Name":"Bundle","Version":"3.0.0","Factory Info":{"Vendor":"Factory Vendor"},
         "Classes":[{"CID":"\(cid)","Category":"\(category)","Name":"\(name)","Vendor":"\(vendor)",
                     "Version":"3.2.9","Sub Categories":\(sub.map { "\"\($0)\"" }.joined(separator: ",").wrapped)}]}
        """
    }
}

private extension String {
    var wrapped: String { "[" + self + "]" }
}

final class PluginBundleReaderTests: XCTestCase {
    func testAudioUnitReadsComponentsFromInfoPlist() {
        let t = makeTemp("au")
        let path = PluginFixtures.component(t, "Components/Falcon.component", components: [
            PluginFixtures.audioComponent(name: "UVI: Falcon", type: "aumu", sub: "Falc", manufacturer: "UVI "),
        ])
        let list = PluginBundleReader.readAudioUnit(bundle: path)
        XCTAssertEqual(list.count, 1)
        let p = list[0]
        XCTAssertEqual(p.uid, "au:aumu:Falc:UVI ")
        XCTAssertEqual(p.name, "Falcon")
        XCTAssertEqual(p.vendor, "UVI")
        XCTAssertEqual(p.version, "1.2.3")               // the bundle's short version wins
        XCTAssertEqual(p.category, "Instrument")
        XCTAssertEqual(p.kind, .audioUnit)
        XCTAssertEqual(p.path, path)
        XCTAssertEqual(p.aliases, [])                     // the file name equals the plugin name
        XCTAssertEqual(p.format, "AU")
    }

    func testAudioUnitUidIsTheSameShapeAsAnAlsRef() {
        // The set stores the codes as 32-bit ints; AlsFile turns them into the same FourCC text.
        var ref = PluginRef(kind: .audioUnit)
        ref.auType = 0x6175_6678; ref.auSubType = 0x726D_7831; ref.auManufacturer = 0x7069_6F6E   // aufx rmx1 pion
        ref.finishUid()
        let t = makeTemp("au-uid")
        let path = PluginFixtures.component(t, "RMX.component", components: [
            PluginFixtures.audioComponent(name: "Pioneer: RMX-1000", type: "aufx", sub: "rmx1", manufacturer: "pion"),
        ])
        XCTAssertEqual(PluginBundleReader.readAudioUnit(bundle: path).first?.uid, ref.uid)
    }

    func testAudioUnitWithSeveralComponentsAndNumericCodes() {
        let t = makeTemp("au-many")
        var numeric = PluginFixtures.audioComponent(name: "Solo", type: "aufx", sub: "abcd", manufacturer: "vend")
        numeric["type"] = 0x6175_6678; numeric["subtype"] = 0x7A7A_7A7A       // "aufx", "zzzz"
        let path = PluginFixtures.component(t, "Suite.component", components: [
            PluginFixtures.audioComponent(name: "Acme: One", type: "aumu", sub: "one ", manufacturer: "acme"),
            numeric,
            ["name": "incomplete"],                                              // no codes: skipped
        ], version: nil)
        let list = PluginBundleReader.readAudioUnit(bundle: path)
        XCTAssertEqual(list.map(\.uid), ["au:aumu:one :acme", "au:aufx:zzzz:vend"])
        XCTAssertEqual(list[1].name, "Solo")
        XCTAssertEqual(list[1].vendor, "")
        XCTAssertEqual(list[0].version, "1.1.1")                                // packed 0x00010101
    }

    func testAudioUnitCategoriesByType() {
        XCTAssertEqual(PluginBundleReader.audioUnitCategory("aumu"), "Instrument")
        XCTAssertEqual(PluginBundleReader.audioUnitCategory("aufx"), "Fx")
        XCTAssertEqual(PluginBundleReader.audioUnitCategory("aumf"), "Fx")
        XCTAssertEqual(PluginBundleReader.audioUnitCategory("aumi"), "MIDI Effect")
        XCTAssertEqual(PluginBundleReader.audioUnitCategory("xxxx"), "")
    }

    func testBrokenOrMissingPlistFallsBackToTheFileName() {
        let t = makeTemp("au-broken")
        t.write("Broken.component/Contents/Info.plist", "not a plist at all <<<")
        t.mkdir("Empty.component/Contents")
        for name in ["Broken", "Empty"] {
            let list = PluginBundleReader.readAudioUnit(bundle: t.sub("\(name).component"))
            XCTAssertEqual(list.count, 1)
            XCTAssertEqual(list[0].name, name)
            XCTAssertEqual(list[0].uid, "file:au:" + PluginInventory.normalize(name))
            XCTAssertTrue(list[0].isFileIdentified)
        }
    }

    func testLegacyThngResourceGivesTheCodes() throws {
        let t = makeTemp("au-rsrc")
        t.mkdir("Old.component/Contents")
        t.write("Old.component/Contents/Info.plist", PluginFixtures.plist(["CFBundleName": "Old"]))
        let data = ResourceForkFixture.file(thng: [("aufx", "dely", "appl"), ("aumu", "synt", "abcd")])
        try FileManager.default.createDirectory(atPath: t.sub("Old.component/Contents/Resources"), withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: t.sub("Old.component/Contents/Resources/Old.rsrc")))
        let list = PluginBundleReader.readAudioUnit(bundle: t.sub("Old.component"))
        XCTAssertEqual(list.map(\.uid), ["au:aufx:dely:appl", "au:aumu:synt:abcd"])
        XCTAssertEqual(list.map(\.name), ["Old", "Old"])
        XCTAssertEqual(list[1].category, "Instrument")
    }

    func testResourceParserSurvivesGarbage() {
        XCTAssertTrue(LegacyComponentResource.components(in: Data()).isEmpty)
        XCTAssertTrue(LegacyComponentResource.components(in: Data(repeating: 0xFF, count: 64)).isEmpty)
        var truncated = ResourceForkFixture.file(thng: [("aufx", "dely", "appl")])
        truncated.removeLast(20)
        _ = LegacyComponentResource.components(in: truncated)            // must not crash
        // A thng that is not an Audio Unit (a QuickTime component) is ignored.
        XCTAssertTrue(LegacyComponentResource.components(in: ResourceForkFixture.file(thng: [("clok", "abcd", "appl")])).isEmpty)
    }

    // MARK: VST3

    func testVst3ModuleInfo() {
        let t = makeTemp("vst3")
        let cid = "56534558667350736572756D20320000"
        let path = PluginFixtures.vst3(t, "VST3/Serum 2.vst3", moduleInfo: PluginFixtures.moduleInfo(cid: cid, name: "Serum 2", vendor: "Xfer Records"))
        let list = PluginBundleReader.readVST3(bundle: path)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].uid, "vst3:56534558-6673-5073-6572-756d20320000")
        XCTAssertEqual(list[0].name, "Serum 2")
        XCTAssertEqual(list[0].vendor, "Xfer Records")
        XCTAssertEqual(list[0].version, "3.2.9")
        XCTAssertEqual(list[0].category, "Fx|EQ")
        XCTAssertEqual(list[0].aliases, [])
    }

    func testVst3UidMatchesAnAlsRef() {
        // Fields "-313016974, 1549813374, -1504849164, 7703407" = FabFilter Pro-Q 4 (see AlsFile).
        var ref = PluginRef(kind: .vst3)
        ref.vst3Fields = [-313_016_974, 1_549_813_374, -1_504_849_164, 7_703_407]; ref.vst3FieldCount = 4
        ref.finishUid()
        XCTAssertEqual(ref.uid, "vst3:ed57bd72-5c60-467e-a64d-d2f400758b6f")
        let t = makeTemp("vst3-uid")
        let path = PluginFixtures.vst3(t, "Q.vst3", moduleInfo: PluginFixtures.moduleInfo(cid: "ED57BD725C60467EA64DD2F400758B6F", name: "Pro-Q 4", vendor: "FabFilter"))
        XCTAssertEqual(PluginBundleReader.readVST3(bundle: path).first?.uid, ref.uid)
    }

    func testVst3SkipsClassesThatAreNotThePlugin() {
        let t = makeTemp("vst3-classes")
        let info = """
        {"Classes":[{"CID":"00000000000000000000000000000001","Category":"Component Controller Class","Name":"Editor"},
                    {"CID":"00000000000000000000000000000002","Category":"Audio Module Class","Name":"Real","Vendor":"V"},
                    {"CID":"tooshort","Category":"Audio Module Class","Name":"Bad"}]}
        """
        let list = PluginBundleReader.readVST3(bundle: PluginFixtures.vst3(t, "Two.vst3", moduleInfo: info))
        XCTAssertEqual(list.map(\.name), ["Real"])
        XCTAssertEqual(list[0].version, "9.9")                          // nothing in JSON: the bundle's
    }

    func testVst3ModuleInfoWithCommentsUsesTheTextScan() {
        let t = makeTemp("vst3-json5")
        let json = """
        // written by hand
        {"Classes":[{"CID":"AABBCCDDEEFF00112233445566778899","Category":"Audio Module Class",
          "Name":"Commented","Vendor":"Someone","Version":"1.0"}, ]}
        """
        let list = PluginBundleReader.readVST3(bundle: PluginFixtures.vst3(t, "C.vst3", moduleInfo: json))
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].uid, "vst3:aabbccdd-eeff-0011-2233-445566778899")
        XCTAssertEqual(list[0].name, "Commented")
    }

    func testVst3TextScanIsUpstreamsReader() {
        let text = #"{"Classes": [ {"CID" : "AABBCCDDEEFF00112233445566778899", "Category": "Audio Module Class", "Name": "N", "Vendor": "V", "Version": "2"} "#
        let list = VST3ModuleInfo.scan(text: text, bundle: "/x/Y.vst3", fallbackName: "Y")
        XCTAssertEqual(list.map(\.name), ["N"])
        XCTAssertEqual(list.first?.vendor, "V")
        XCTAssertTrue(VST3ModuleInfo.scan(text: "garbage", bundle: "/x/Y.vst3", fallbackName: "Y").isEmpty)
    }

    func testVst3WithoutModuleInfoIsIdentifiedByFile() {
        let t = makeTemp("vst3-plain")
        let path = PluginFixtures.vst3(t, "Vendor/Plain Synth.vst3")
        let list = PluginBundleReader.readVST3(bundle: path)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].name, "Plain Synth")
        XCTAssertEqual(list[0].uid, "file:vst3:plainsynth")
        XCTAssertEqual(list[0].version, "9.9")
        // An unusable moduleinfo.json does not lose the plugin either.
        let bad = PluginFixtures.vst3(t, "Bad.vst3", moduleInfo: "{ nope")
        XCTAssertEqual(PluginBundleReader.readVST3(bundle: bad).first?.uid, "file:vst3:bad")
    }

    func testVst2IsIdentifiedByFileNotBySignature() {
        let t = makeTemp("vst2")
        t.write("Sylenth1.vst/Contents/Info.plist", PluginFixtures.plist(["CFBundleSignature": "FabF", "CFBundleShortVersionString": "3.0"]))
        let list = PluginBundleReader.readVST2(bundle: t.sub("Sylenth1.vst"))
        XCTAssertEqual(list.first?.uid, "file:vst2:sylenth1")
        XCTAssertEqual(list.first?.version, "3.0")
        XCTAssertEqual(list.first?.format, "VST2")
    }

    func testFourCCConversions() {
        XCTAssertEqual(PluginBundleReader.fourCC("aufx"), "aufx")
        XCTAssertEqual(PluginBundleReader.fourCC("Pro "), "Pro ")
        XCTAssertNil(PluginBundleReader.fourCC("toolong"))
        XCTAssertNil(PluginBundleReader.fourCC(nil))
        XCTAssertEqual(PluginBundleReader.fourCC(NSNumber(value: 0x6175_6678)), "aufx")
    }
}

/// Builds the data fork of a resource file holding `thng` resources.
enum ResourceForkFixture {
    static func file(thng: [(String, String, String)]) -> Data {
        func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
        func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 255), UInt8(v & 255)] }
        // Data section: [length][type sub manufacturer flags mask]…
        var dataSection: [UInt8] = []
        var offsets: [Int] = []
        for (t, s, m) in thng {
            offsets.append(dataSection.count)
            let body = Array(t.utf8) + Array(s.utf8) + Array(m.utf8) + be32(0) + be32(0)
            dataSection += be32(body.count) + body
        }
        let dataOffset = 256
        // Map: 16-byte header copy, 4 handle, 2 file ref, 2 attrs, 2 type list offset, 2 name list offset.
        let typeListOffset = 28
        var map = [UInt8](repeating: 0, count: 24)
        map += be16(typeListOffset) + be16(0)
        // Type list: count-1, then one entry: 'thng', refs-1, offset of ref list from the type list.
        map += be16(0) + Array("thng".utf8) + be16(thng.count - 1) + be16(10)
        for (i, off) in offsets.enumerated() {
            map += be16(128 + i) + be16(0xFFFF) + [0] + Array(be32(off).dropFirst()) + be32(0)
        }
        let mapOffset = dataOffset + dataSection.count
        var out = be32(dataOffset) + be32(mapOffset) + be32(dataSection.count) + be32(map.count)
        out += [UInt8](repeating: 0, count: dataOffset - out.count)
        out += dataSection
        out += map
        return Data(out)
    }
}
