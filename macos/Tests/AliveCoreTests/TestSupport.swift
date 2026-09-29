import Foundation
import XCTest
@testable import AliveCore

/// A unique temp folder, removed on `cleanup()` (register with `addTeardownBlock`).
final class TempDir {
    let path: String
    init(_ label: String = "alive") {
        path = NSTemporaryDirectory() + "\(label)-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
    func cleanup() { try? FileManager.default.removeItem(atPath: path) }
    func sub(_ rel: String) -> String { path + "/" + rel }

    @discardableResult
    func mkdir(_ rel: String) -> String {
        try? FileManager.default.createDirectory(atPath: sub(rel), withIntermediateDirectories: true)
        return sub(rel)
    }

    @discardableResult
    func write(_ rel: String, _ text: String = "x") -> String {
        let p = sub(rel)
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: URL(fileURLWithPath: p))
        return p
    }

    /// Writes a gzipped .als built from `xml`.
    @discardableResult
    func als(_ rel: String, _ xml: String, modified: Date? = nil) -> String {
        let p = sub(rel)
        try? FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        let gz = try! Gzip.compress(Data(xml.utf8))
        try! gz.write(to: URL(fileURLWithPath: p))
        if let modified { setModified(p, modified) }
        return p
    }

    func setModified(_ path: String, _ date: Date) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }
}

extension XCTestCase {
    func makeTemp(_ label: String = "alive") -> TempDir {
        let t = TempDir(label)
        addTeardownBlock { t.cleanup() }
        return t
    }
}

/// XML builders shaped like real Live sets.
enum Fx {
    static func als(creator: String = "Ableton Live 12.3.5", live: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            + "<Ableton MajorVersion=\"5\" MinorVersion=\"12.0_12300\" Creator=\"\(creator)\">"
            + "<LiveSet>\(live)</LiveSet></Ableton>"
    }

    static func tracks(_ inner: String) -> String { "<Tracks>\(inner)</Tracks>" }

    static func track(_ kind: String, id: Int = 1, name: String = "T", extra: String = "") -> String {
        "<\(kind) Id=\"\(id)\"><Name><EffectiveName Value=\"\(name)\"/></Name>\(extra)</\(kind)>"
    }

    static func main(tag: String = "MainTrack", tempo: Double) -> String {
        "<\(tag) Id=\"9\"><DeviceChain><Mixer><Tempo><LomId Value=\"0\"/><Manual Value=\"\(tempo)\"/>"
            + "</Tempo></Mixer></DeviceChain></\(tag)>"
    }

    static func scale(root: Int, name: Int, flat: Bool = false) -> String {
        "<ScaleInformation><Root Value=\"\(root)\"/><Name Value=\"\(name)\"/></ScaleInformation>"
            + "<PreferFlatRootNote Value=\"\(flat)\"/>"
    }

    static func vst3(name: String, fields: [Int32], browser: String? = nil) -> String {
        let f = fields.enumerated().map { "<Fields.\($0.offset) Value=\"\($0.element)\"/>" }.joined()
        let bcp = browser.map { "<BrowserContentPath Value=\"\($0)\"/>" } ?? ""
        return bcp + "<PluginDesc><Vst3PluginInfo Id=\"0\"><WinPosX Value=\"1\"/><Name Value=\"\(name)\"/>"
            + "<Uid>\(f)</Uid><Preset><Vst3Preset><Name Value=\"\"/></Vst3Preset></Preset></Vst3PluginInfo></PluginDesc>"
    }

    static func vst2(name: String, uniqueId: Int, browser: String? = nil) -> String {
        let bcp = browser.map { "<BrowserContentPath Value=\"\($0)\"/>" } ?? ""
        return bcp + "<PluginDesc><VstPluginInfo Id=\"0\"><Path Value=\"C:\\VST\\x.dll\"/>"
            + "<PlugName Value=\"\(name)\"/><UniqueId Value=\"\(uniqueId)\"/></VstPluginInfo></PluginDesc>"
    }

    static func au(name: String, vendor: String, type: Int, sub: Int, mfr: Int) -> String {
        "<PluginDesc><AuPluginInfo Id=\"0\"><WinPosX Value=\"47\"/><ComponentType Value=\"\(type)\"/>"
            + "<ComponentSubType Value=\"\(sub)\"/><ComponentManufacturer Value=\"\(mfr)\"/>"
            + "<ComponentFlags Value=\"268435456\"/><Name Value=\"\(name)\"/><Manufacturer Value=\"\(vendor)\"/>"
            + "<Preset><AuPreset><Name Value=\"\"/></AuPreset></Preset></AuPluginInfo></PluginDesc>"
    }

    static func fileRef(parent: String = "SampleRef", rel: String, abs: String, type: Int,
                        pack: String = "", size: Int = 0) -> String {
        "<\(parent)><FileRef><RelativePathType Value=\"\(type)\"/><RelativePath Value=\"\(rel)\"/>"
            + "<Path Value=\"\(abs)\"/><Type Value=\"2\"/><LivePackName Value=\"\(pack)\"/>"
            + "<LivePackId Value=\"\"/><OriginalFileSize Value=\"\(size)\"/></FileRef></\(parent)>"
    }

    /// A tiny complete set: 1 audio + 1 midi + 1 group track, main tempo, key.
    static func simpleSet(tempo: Double = 128, extra: String = "") -> String {
        als(live: tracks(track("AudioTrack", id: 1) + track("MidiTrack", id: 2) + track("GroupTrack", id: 3))
            + main(tempo: tempo) + scale(root: 0, name: 1) + extra)
    }
}

/// A thread-safe counter for callbacks that fire on background threads.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func bump() { lock.lock(); n += 1; lock.unlock() }
    func raise(to v: Int) { lock.lock(); n = max(n, v); lock.unlock() }
}
