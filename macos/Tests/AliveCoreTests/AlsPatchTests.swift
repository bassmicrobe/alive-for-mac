import CryptoKit
import XCTest
@testable import AliveCore

/// Sets shaped like the ones Live for Mac writes: one tag per line, tabs, LF endings, plugin
/// nodes with a hex "Buffer" blob.
enum RescueFx {
    static func pretty(_ xml: String) -> String { xml.replacingOccurrences(of: "><", with: ">\n<") }

    static let blob = "<Buffer>\n3C3F786D6C2076657273696F6E3D22312E30\n21444F435459504520706C697374205055424C\n</Buffer>"

    static func vst3(_ name: String, _ f: [Int32]) -> String {
        let uid = f.enumerated().map { "<Fields.\($0.offset) Value=\"\($0.element)\" />" }.joined()
        return "<PluginDevice Id=\"1\"><PluginDesc><Vst3PluginInfo Id=\"0\"><WinPosX Value=\"1\" /><Name Value=\"\(name)\" />"
            + "<Uid>\(uid)</Uid><DeviceType Value=\"1\" /><Preset><Vst3Preset Id=\"2\"><Name Value=\"\" />"
            + "<Uid>\(uid)</Uid>\(blob)</Vst3Preset></Preset></Vst3PluginInfo></PluginDesc></PluginDevice>"
    }

    static func vst2(_ name: String, id: Int32, path: String = "/Library/Audio/Plug-Ins/VST/Old.vst") -> String {
        "<PluginDevice Id=\"3\"><PluginDesc><VstPluginInfo Id=\"0\"><Path Value=\"\(path)\" /><PlugName Value=\"\(name)\" />"
            + "<UniqueId Value=\"\(id)\" /><Preset><VstPreset Id=\"4\"><Path Value=\"\(path)\" />\(blob)</VstPreset></Preset>"
            + "</VstPluginInfo></PluginDesc></PluginDevice>"
    }

    static func au(_ name: String, vendor: String = "Pioneer Corporation", type: UInt32 = 1_635_085_670,
                   sub: UInt32 = 909_342_512, mfr: UInt32 = 1_349_087_086) -> String {
        "<PluginDevice Id=\"5\"><PluginDesc><AuPluginInfo Id=\"0\"><WinPosX Value=\"47\" /><ComponentType Value=\"\(type)\" />"
            + "<ComponentSubType Value=\"\(sub)\" /><ComponentManufacturer Value=\"\(mfr)\" /><ComponentFlags Value=\"268435456\" />"
            + "<Name Value=\"\(name)\" /><Manufacturer Value=\"\(vendor)\" /><Preset><AuPreset Id=\"6\">\(blob)</AuPreset></Preset>"
            + "</AuPluginInfo></PluginDesc></PluginDevice>"
    }

    /// A pretty-printed set holding the given device XML and file references.
    static func set(devices: [String], refs: [String] = [], extra: String = "") -> String {
        let body = "<Tracks><AudioTrack Id=\"1\"><Name><EffectiveName Value=\"T\" /></Name>"
            + devices.joined() + refs.joined() + "</AudioTrack></Tracks>"
            + "<MainTrack Id=\"9\"><DeviceChain><Mixer><Tempo><Manual Value=\"120\" /></Tempo></Mixer></DeviceChain></MainTrack>"
            + extra
        return pretty(Fx.als(live: body)).replacingOccurrences(of: "\n<", with: "\n\t<")
    }

    static let serum = vst3("Serum", [-1_412_567_295, 1_549_813_374, -1_504_849_164, 7_703_407])
    static let proQ = vst3("Pro-Q 3", [-313_016_974, 1_549_813_374, -1_504_849_164, 7_703_408])
    static let pumper = vst2("OneKnob Pumper", id: 1_483_109_208)
    static let rmx = au("RMX-1000 Plug-in")
    static let ssl = au("SSL Native Bus Compressor 2", vendor: "Solid State Logic", sub: 1_936_745_522, mfr: 1_400_338_534)

    static func sha(_ path: String) -> String {
        let d = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    static func lines(of als: String) throws -> [String] {
        String(decoding: try Gzip.readMaybeGzip(path: als), as: UTF8.self).components(separatedBy: "\n")
    }
}

final class AlsPatchTests: XCTestCase {
    private func makeSet(_ t: TempDir, devices: [String] = [RescueFx.serum, RescueFx.pumper, RescueFx.rmx, RescueFx.proQ],
                         name: String = "Song") -> String {
        t.als("Song Project/\(name).als", RescueFx.set(devices: devices))
    }

    // MARK: targets

    func testTargetsIncludeAllThreeFormatsSortedAndCounted() {
        let t = makeTemp()
        let path = makeSet(t, devices: [RescueFx.serum, RescueFx.serum, RescueFx.pumper, RescueFx.rmx, RescueFx.proQ])
        let slots = AlsPatch.targets(AlsFile.read(path: path))
        XCTAssertEqual(slots.map(\.name), ["OneKnob Pumper", "Pro-Q 3", "RMX-1000 Plug-in", "Serum"])
        XCTAssertEqual(slots.map(\.format), ["VST2", "VST3", "AU", "VST3"])
        XCTAssertEqual(slots.first { $0.name == "Serum" }?.count, 2)
        XCTAssertEqual(slots.first { $0.name == "RMX-1000 Plug-in" }?.vendor, "Pioneer Corporation")
        XCTAssertTrue(slots.first { $0.name == "RMX-1000 Plug-in" }!.uid.hasPrefix("au:"))
        XCTAssertEqual(AlsPatch.unaddressable(AlsFile.read(path: path)), 0)
        XCTAssertTrue(AlsPatch.targets(nil).isEmpty)
    }

    // MARK: neutralize

    private func neutralize(_ src: String, _ dst: String, uids: [String], inv: PluginInventory? = nil) throws -> Int {
        try AlsPatch.neutralize(src: src, dst: dst, uids: uids, inventory: inv)
    }

    func testOnlyTheTargetedVst3IsDisabledAndEverythingElseIsByteIdentical() throws {
        let t = makeTemp()
        let src = makeSet(t)
        let before = RescueFx.sha(src)
        let slots = AlsPatch.targets(AlsFile.read(path: src))
        let serum = slots.first { $0.name == "Serum" }!

        let dst = t.sub("Song Project/Song.alive-probe.als")
        XCTAssertEqual(try neutralize(src, dst, uids: [serum.uid]), 1)

        // The patched file is a valid gzip set; only Serum's identifier changed.
        let after = AlsPatch.targets(AlsFile.read(path: dst))
        XCTAssertEqual(after.count, slots.count)
        XCTAssertEqual(after.map(\.name), slots.map(\.name))
        for (a, b) in zip(after, slots) {
            if a.name == "Serum" { XCTAssertNotEqual(a.uid, b.uid) } else { XCTAssertEqual(a.uid, b.uid, a.name) }
        }

        let l0 = try RescueFx.lines(of: src), l1 = try RescueFx.lines(of: dst)
        XCTAssertEqual(l0.count, l1.count)
        let changed = zip(l0, l1).filter { $0 != $1 }
        XCTAssertEqual(changed.count, 2, "Fields.0 of both <Uid> blocks")          // device + preset copy
        for (a, _) in changed { XCTAssertTrue(a.trimmingCharacters(in: .whitespaces).hasPrefix("<Fields.0 ")) }
        XCTAssertEqual(RescueFx.sha(src), before, "the original is never touched")
    }

    func testVst2GetsBrokenIdAndPath() throws {
        let t = makeTemp()
        let src = makeSet(t)
        let pumper = AlsPatch.targets(AlsFile.read(path: src)).first { $0.kind == .vst2 }!
        let dst = t.sub("out.als")
        XCTAssertEqual(try neutralize(src, dst, uids: [pumper.uid]), 1)

        let text = try RescueFx.lines(of: dst).joined(separator: "\n")
        XCTAssertFalse(text.contains("<UniqueId Value=\"1483109208\""))
        XCTAssertTrue(text.contains("Old.vst.alive-disabled"))
        XCTAssertFalse(text.contains("Old.vst\" "), "every path in the node is suffixed")
        let l0 = try RescueFx.lines(of: src), l1 = try RescueFx.lines(of: dst)
        for (a, b) in zip(l0, l1) where a != b {
            let tag = a.trimmingCharacters(in: .whitespaces)
            XCTAssertTrue(tag.hasPrefix("<UniqueId ") || tag.hasPrefix("<Path "), tag)
            XCTAssertTrue(b.contains("alive-disabled") || b.contains("<UniqueId "))
        }
    }

    func testAudioUnitIsDisabledAndItsNameAndTypeSurvive() throws {
        let t = makeTemp()
        let src = makeSet(t)
        let rmx = AlsPatch.targets(AlsFile.read(path: src)).first { $0.kind == .audioUnit }!
        let dst = t.sub("out.als")
        XCTAssertEqual(try neutralize(src, dst, uids: [rmx.uid]), 1)

        let now = AlsPatch.targets(AlsFile.read(path: dst)).first { $0.kind == .audioUnit }!
        XCTAssertEqual(now.name, "RMX-1000 Plug-in")
        XCTAssertNotEqual(now.uid, rmx.uid)
        XCTAssertEqual(now.uid.split(separator: ":")[1], rmx.uid.split(separator: ":")[1], "component type kept")
        let l0 = try RescueFx.lines(of: src), l1 = try RescueFx.lines(of: dst)
        let changed = zip(l0, l1).filter { $0 != $1 }.map { $0.0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(changed.count, 2)
        XCTAssertTrue(changed.allSatisfy { $0.hasPrefix("<ComponentSubType ") || $0.hasPrefix("<ComponentManufacturer ") })
    }

    func testAudioUnitPreservesIndependentSignedDecimalConventions() throws {
        let t = makeTemp()
        let manufacturer: UInt32 = 0xF000_0001
        let device = RescueFx.au("Mixed Codes", sub: 909_342_512, mfr: manufacturer)
        let mixed = device.replacingOccurrences(of: String(manufacturer),
                                                with: String(Int32(bitPattern: manufacturer)))
        let src = makeSet(t, devices: [mixed])
        let uid = try XCTUnwrap(AlsPatch.targets(AlsFile.read(path: src)).first?.uid)
        let dst = t.sub("out.als")
        XCTAssertEqual(try neutralize(src, dst, uids: [uid]), 1)
        let xml = try RescueFx.lines(of: dst).joined(separator: "\n")
        let sub = try XCTUnwrap(AlsPatch.firstLong(xml, "<ComponentSubType Value=\""))
        let man = try XCTUnwrap(AlsPatch.firstLong(xml, "<ComponentManufacturer Value=\""))
        XCTAssertEqual(sub, Int64(909_342_512 ^ UInt32(bitPattern: AlsPatch.marker)))
        XCTAssertEqual(man, Int64(Int32(bitPattern: manufacturer ^ UInt32(bitPattern: AlsPatch.marker))))
        XCTAssertNotEqual(AlsPatch.targets(AlsFile.read(path: dst)).first?.uid, uid)
    }

    func testAudioUnitRefusesAllOccupiedIdentifiersAndRemovesPartialCopy() throws {
        let t = makeTemp()
        let src = makeSet(t, devices: [RescueFx.rmx])
        let uid = try XCTUnwrap(AlsPatch.targets(AlsFile.read(path: src)).first?.uid)
        let before = RescueFx.sha(src)
        let type: UInt32 = 1_635_085_670, sub: UInt32 = 909_342_512, manufacturer: UInt32 = 1_349_087_086
        let mark = UInt32(bitPattern: AlsPatch.marker)
        var inv = PluginInventory()
        for bump in UInt32(0)..<64 {
            var ref = PluginRef(kind: .audioUnit)
            ref.auType = type
            ref.auSubType = sub ^ (mark &+ bump)
            ref.auManufacturer = manufacturer ^ (mark &+ bump)
            ref.finishUid()
            var plugin = InstalledPlugin()
            plugin.uid = ref.uid
            plugin.name = "Occupied \(bump)"
            inv.add(plugin)
        }
        let dst = t.sub("out.als")
        XCTAssertThrowsError(try neutralize(src, dst, uids: [uid], inv: inv)) {
            XCTAssertEqual($0 as? RescueError, .noFreeIdentifier)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst))
        XCTAssertEqual(RescueFx.sha(src), before)
    }

    func testSeveralPluginsAtOnceAndDuplicatesAreAllPatched() throws {
        let t = makeTemp()
        let src = makeSet(t, devices: [RescueFx.serum, RescueFx.serum, RescueFx.rmx, RescueFx.ssl, RescueFx.pumper])
        let all = AlsPatch.targets(AlsFile.read(path: src))
        let dst = t.sub("out.als")
        XCTAssertEqual(try neutralize(src, dst, uids: all.map(\.uid)), 5, "two Serum copies count twice")
        let uidsAfter = Set(AlsPatch.targets(AlsFile.read(path: dst)).map(\.uid))
        XCTAssertTrue(uidsAfter.isDisjoint(with: Set(all.map(\.uid))))
        XCTAssertEqual(uidsAfter.count, all.count, "two disabled plugins do not collapse into one identifier")
    }

    func testUnknownUidPatchesNothing() throws {
        let t = makeTemp()
        let src = makeSet(t)
        let dst = t.sub("out.als")
        XCTAssertEqual(try neutralize(src, dst, uids: ["vst3:00000000-0000-0000-0000-000000000000"]), 0)
        XCTAssertThrowsError(try neutralize(src, dst, uids: []))
    }

    func testUnpatchedCopyRoundTripsByteForByteAfterInflate() throws {
        let t = makeTemp()
        // A big set: 20k blob lines exercise the streaming chunks.
        let blob = (0..<20_000).map { String(format: "%08X%08X", $0, $0 &* 7) }.joined(separator: "\n")
        let src = t.als("Big Project/Big.als", RescueFx.set(devices: [RescueFx.serum], extra: "<Bulk>\n\(blob)\n</Bulk>"))
        let dst = t.sub("Big Project/copy.als")
        XCTAssertEqual(try neutralize(src, dst, uids: ["vst3:none"]), 0)
        XCTAssertEqual(try Gzip.readMaybeGzip(path: src), try Gzip.readMaybeGzip(path: dst))
    }

    func testCrLfAndPlainXmlInputAreHandled() throws {
        let t = makeTemp()
        let xml = RescueFx.set(devices: [RescueFx.serum]).replacingOccurrences(of: "\n", with: "\r\n")
        let plain = t.write("plain.als", xml)                         // not gzip at all
        let serum = AlsPatch.targets(AlsFile.read(path: plain))[0]
        let dst = t.sub("out.als")
        XCTAssertEqual(try neutralize(plain, dst, uids: [serum.uid]), 1)
        let out = String(decoding: try Gzip.readMaybeGzip(path: dst), as: UTF8.self)
        XCTAssertEqual(out.components(separatedBy: "\r\n").count, xml.components(separatedBy: "\r\n").count)
        XCTAssertNotEqual(AlsPatch.targets(AlsFile.read(path: dst))[0].uid, serum.uid)
    }

    func testMarkerAvoidsInstalledPlugins() throws {
        let t = makeTemp()
        let src = makeSet(t, devices: [RescueFx.serum])
        let serum = AlsPatch.targets(AlsFile.read(path: src))[0]

        // Pretend the first marker candidate belongs to an installed plugin.
        var clash = PluginRef(kind: .vst3)
        clash.vst3Fields = [AlsPatch.marker, 1_549_813_374, -1_504_849_164, 7_703_407]
        clash.vst3FieldCount = 4
        clash.finishUid()
        var inv = PluginInventory()
        var p = InstalledPlugin()
        p.uid = clash.uid
        p.name = "Impostor"
        inv.add(p)

        let dst = t.sub("out.als")
        XCTAssertEqual(try neutralize(src, dst, uids: [serum.uid], inv: inv), 1)
        let now = AlsPatch.targets(AlsFile.read(path: dst))[0]
        XCTAssertNotEqual(now.uid, clash.uid)
        XCTAssertNil(inv.byUid(now.uid))
    }

    func testFailureRemovesThePartialCopyAndLeavesTheSourceAlone() throws {
        let t = makeTemp()
        let dst = t.sub("out.als")
        XCTAssertThrowsError(try neutralize(t.sub("missing.als"), dst, uids: ["x"]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst))

        let src = makeSet(t)
        let before = RescueFx.sha(src)
        struct Stop: Error {}
        XCTAssertThrowsError(try AlsPatch.neutralize(src: src, dst: dst, uids: ["x"]) { true }) { e in
            XCTAssertTrue(e is CancellationError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst))
        XCTAssertEqual(RescueFx.sha(src), before)
    }

    func testSelfClosingNodeDoesNotSwallowTheRestOfTheFile() throws {
        let t = makeTemp()
        let devices = ["<X><VstPluginInfo Id=\"0\" /></X>", RescueFx.serum]
        let src = t.als("s.als", RescueFx.set(devices: devices))
        let serum = AlsPatch.targets(AlsFile.read(path: src))[0]
        XCTAssertEqual(try neutralize(src, t.sub("out.als"), uids: [serum.uid]), 1)
    }

    /// Real-library smoke test (gated like the others): a COPY of the first set found under
    /// `ALIVE_TEST_SETS` gets every plugin disabled; only identifier lines may differ.
    func testRealSetCopyDisablesEveryPluginOnlyThroughIdentifiers() throws {
        guard let root = ProcessInfo.processInfo.environment["ALIVE_TEST_SETS"] else {
            throw XCTSkip("ALIVE_TEST_SETS not set")
        }
        var found: String?
        _ = FolderScan.find(root: root, ext: ".als", includeBackups: false, onFile: { if found == nil { found = $0 } })
        let real = try XCTUnwrap(found)
        let t = makeTemp()
        let src = t.sub("Copy Project/Real.als")
        try FileManager.default.createDirectory(atPath: (src as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: real, toPath: src)

        let info = AlsFile.read(path: src)
        let slots = AlsPatch.targets(info)
        guard !slots.isEmpty else { throw XCTSkip("first set has no plugins") }
        let dst = t.sub("Copy Project/Real.alive-probe.als")
        XCTAssertGreaterThan(try neutralize(src, dst, uids: slots.map(\.uid)), 0)
        let l0 = try RescueFx.lines(of: src), l1 = try RescueFx.lines(of: dst)
        XCTAssertEqual(l0.count, l1.count)
        for (a, b) in zip(l0, l1) where a != b {
            let tag = a.trimmingCharacters(in: .whitespaces)
            XCTAssertTrue(["<Fields.0 ", "<UniqueId ", "<Path ", "<ComponentSubType ", "<ComponentManufacturer "].contains { tag.hasPrefix($0) }, tag)
            XCTAssertNotEqual(a, b)
        }
        let after = AlsPatch.targets(AlsFile.read(path: dst))
        XCTAssertEqual(after.map(\.name), slots.map(\.name))
        XCTAssertTrue(Set(after.map(\.uid)).isDisjoint(with: Set(slots.map(\.uid))))
    }
}
