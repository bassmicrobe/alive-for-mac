// Mac-only: reads the metadata of one plugin bundle without loading its code. Upstream reads
// Live's database instead and only walks VST3 folders as a fallback (PluginInventory.AddBundle /
// ReadModuleInfo); on macOS the bundles are the primary source.
import Foundation

enum PluginBundleReader {
    /// `Contents/Info.plist` as a dictionary; nil when absent or broken (logged when broken).
    static func infoPlist(_ bundle: String) -> [String: Any]? {
        let path = bundle + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        do {
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        } catch {
            Diag.warn("plugins: unreadable Info.plist in \(bundle)")
            return nil
        }
    }

    static func baseName(_ bundle: String) -> String {
        ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private static func bundleVersion(_ plist: [String: Any]?) -> String {
        (plist?["CFBundleShortVersionString"] as? String)
            ?? (plist?["CFBundleVersion"] as? String) ?? ""
    }

    /// A plugin known by its file alone.
    private static func fileOnly(_ bundle: String, kind: PluginKind, plist: [String: Any]?) -> InstalledPlugin {
        var p = InstalledPlugin()
        p.kind = kind
        p.name = baseName(bundle)
        p.path = bundle
        p.version = bundleVersion(plist)
        p.uid = InstalledPlugin.fileUid(kind: kind, name: p.name)
        return p
    }

    // MARK: - Audio Units

    /// `.component`: `AudioComponents[]` in Info.plist, else the legacy `thng` resource in a
    /// `.rsrc` file, else the file name.
    static func readAudioUnit(bundle: String) -> [InstalledPlugin] {
        let plist = infoPlist(bundle)
        let base = baseName(bundle)
        var out: [InstalledPlugin] = []
        for c in plist?["AudioComponents"] as? [[String: Any]] ?? [] {
            guard let type = fourCC(c["type"]), let sub = fourCC(c["subtype"]),
                  let manufacturer = fourCC(c["manufacturer"]) else { continue }
            out.append(audioUnit(bundle, plist: plist, type: type, sub: sub, manufacturer: manufacturer,
                                 fullName: c["name"] as? String ?? base, version: c["version"], base: base))
        }
        if !out.isEmpty { return out }

        for r in LegacyComponentResource.read(bundle: bundle) {
            out.append(audioUnit(bundle, plist: plist, type: r.type, sub: r.subtype, manufacturer: r.manufacturer,
                                 fullName: base, version: nil, base: base))
        }
        return out.isEmpty ? [fileOnly(bundle, kind: .audioUnit, plist: plist)] : out
    }

    private static func audioUnit(_ bundle: String, plist: [String: Any]?, type: String, sub: String,
                                  manufacturer: String, fullName: String, version: Any?, base: String) -> InstalledPlugin {
        var p = InstalledPlugin()
        p.kind = .audioUnit
        p.path = bundle
        p.uid = "au:\(type):\(sub):\(manufacturer)"
        // The name reads "Vendor: Plugin" — the same split Live's browser makes.
        if let colon = fullName.range(of: ": ") {
            p.vendor = String(fullName[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
            p.name = String(fullName[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if p.name.isEmpty { p.name = fullName }
        let shortVersion = plist?["CFBundleShortVersionString"] as? String
        p.version = shortVersion ?? packedVersion(version) ?? bundleVersion(plist)
        p.category = audioUnitCategory(type)
        if base != p.name { p.aliases = [base] }
        return p
    }

    /// The component type as Live groups it: instruments ("aumu"), effects and MIDI effects.
    static func audioUnitCategory(_ type: String) -> String {
        switch type {
        case "aumu", "augn": return "Instrument"
        case "aufx", "aumf", "aufc", "aumx", "aupn": return "Fx"
        case "aumi": return "MIDI Effect"
        default: return ""
        }
    }

    /// A four-character code from a plist string or number.
    static func fourCC(_ value: Any?) -> String? {
        if let n = value as? NSNumber, !(value is String) { return AlsFile.fourCC(n.uint32Value) }
        guard let s = value as? String, !s.isEmpty else { return nil }
        let bytes = Array(s.utf8)
        if s.unicodeScalars.count == 4, bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) { return s }
        return s.count == 4 ? s : nil
    }

    /// 0xMMMMmmbb as "M.m.b".
    private static func packedVersion(_ value: Any?) -> String? {
        guard let n = value as? NSNumber else { return nil }
        let v = n.uint32Value
        return "\(v >> 16).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }

    // MARK: - VST3

    /// `.vst3`: moduleinfo.json (every "Audio Module Class"), else just the bundle.
    static func readVST3(bundle: String) -> [InstalledPlugin] {
        let plist = infoPlist(bundle)
        let info = bundle + "/Contents/Resources/moduleinfo.json"
        if let data = FileManager.default.contents(atPath: info) {
            let found = VST3ModuleInfo.classes(in: data, bundle: bundle, fallbackName: baseName(bundle),
                                               fallbackVersion: bundleVersion(plist))
            if !found.isEmpty { return found }
            Diag.warn("plugins: no plugin classes in \(info)")
        }
        return [fileOnly(bundle, kind: .vst3, plist: plist)]
    }

    // MARK: - VST2

    /// `.vst`: the identifier lies in the binary; CFBundleSignature is often a vendor code shared
    /// by all of a vendor's plugins, so the plugin is identified by name.
    static func readVST2(bundle: String) -> [InstalledPlugin] {
        [fileOnly(bundle, kind: .vst2, plist: infoPlist(bundle))]
    }
}

/// moduleinfo.json (VST 3.7.5 module info): the class list.
enum VST3ModuleInfo {
    static func classes(in data: Data, bundle: String, fallbackName: String, fallbackVersion: String) -> [InstalledPlugin] {
        let root = (try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed])) as? [String: Any]
        guard let root, let list = root["Classes"] as? [[String: Any]] else {
            // Not strict JSON (comments, stray commas): fall back to the upstream text scan.
            return scan(text: String(decoding: data, as: UTF8.self), bundle: bundle, fallbackName: fallbackName)
        }
        let factory = root["Factory Info"] as? [String: Any]
        var out: [InstalledPlugin] = []
        for c in list where (c["Category"] as? String) == "Audio Module Class" {
            guard let cid = c["CID"] as? String, cid.count == 32 else { continue }
            var p = InstalledPlugin()
            p.kind = .vst3
            p.uid = "vst3:" + dashed(cid)
            p.name = (c["Name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
            p.vendor = (c["Vendor"] as? String) ?? (factory?["Vendor"] as? String) ?? ""
            p.version = (c["Version"] as? String) ?? (root["Version"] as? String) ?? fallbackVersion
            p.category = (c["Sub Categories"] as? [String] ?? []).joined(separator: "|")
            p.path = bundle
            if fallbackName != p.name { p.aliases = [fallbackName] }
            out.append(p)
        }
        return out
    }

    /// Upstream's reader: cut the text at every "CID" and look at the chunk up to the next one.
    static func scan(text: String, bundle: String, fallbackName: String) -> [InstalledPlugin] {
        let parts = text.components(separatedBy: "\"CID\"")
        var out: [InstalledPlugin] = []
        for chunk in parts.dropFirst() where chunk.contains("Audio Module Class") {
            guard let cid = firstString(chunk, from: chunk.startIndex), cid.count == 32 else { continue }
            var p = InstalledPlugin()
            p.kind = .vst3
            p.uid = "vst3:" + dashed(cid)
            p.name = field(chunk, "\"Name\"") ?? fallbackName
            p.vendor = field(chunk, "\"Vendor\"") ?? ""
            p.version = field(chunk, "\"Version\"") ?? ""
            p.path = bundle
            out.append(p)
        }
        return out
    }

    /// «56534558667350736572756D20320000» -> «56534558-6673-5073-6572-756d20320000».
    static func dashed(_ cid: String) -> String {
        let c = Array(cid.lowercased())
        func part(_ a: Int, _ b: Int) -> String { String(c[a..<b]) }
        return [part(0, 8), part(8, 12), part(12, 16), part(16, 20), part(20, 32)].joined(separator: "-")
    }

    private static func field(_ chunk: String, _ key: String) -> String? {
        guard let at = chunk.range(of: key) else { return nil }
        return firstString(chunk, from: at.upperBound)
    }

    /// The first quoted string starting from `from` — the value after the colon.
    private static func firstString(_ s: String, from: String.Index) -> String? {
        guard let open = s[from...].firstIndex(of: "\"") else { return nil }
        let after = s.index(after: open)
        guard let close = s[after...].firstIndex(of: "\"") else { return nil }
        return String(s[after..<close])
    }
}

/// Old Audio Units keep their registration in a `thng` resource inside `Contents/Resources/*.rsrc`
/// (a resource file in the data fork) instead of Info.plist.
enum LegacyComponentResource {
    struct Component: Equatable {
        let type: String, subtype: String, manufacturer: String
    }

    private static let maxFileSize = 32 << 20

    static func read(bundle: String) -> [Component] {
        let dir = bundle + "/Contents/Resources"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [Component] = []
        for n in names.sorted() where n.lowercased().hasSuffix(".rsrc") {
            let path = dir + "/" + n
            let size = FileStat.of(path).map { Int($0.size) }
            guard let size, size > 16, size <= maxFileSize,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { continue }
            out.append(contentsOf: components(in: data))
        }
        return out
    }

    /// The `thng` resources of a resource file whose component type is an Audio Unit type.
    static func components(in data: Data) -> [Component] {
        func u32(_ at: Int) -> Int? {
            guard at >= 0, at + 4 <= data.count else { return nil }
            return data[data.startIndex + at ..< data.startIndex + at + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        func u16(_ at: Int) -> Int? {
            guard at >= 0, at + 2 <= data.count else { return nil }
            return Int(data[data.startIndex + at]) << 8 | Int(data[data.startIndex + at + 1])
        }
        func code(_ at: Int) -> String? {
            guard at >= 0, at + 4 <= data.count else { return nil }
            return String(bytes: data[data.startIndex + at ..< data.startIndex + at + 4], encoding: .isoLatin1)
        }
        guard let dataOffset = u32(0), let mapOffset = u32(4),
              let typeListOffset = u16(mapOffset + 24), let typeCount = u16(mapOffset + typeListOffset) else { return [] }
        let list = mapOffset + typeListOffset
        var out: [Component] = []
        for i in 0...typeCount {                      // the stored count is "number of types - 1"
            let entry = list + 2 + i * 8
            guard code(entry) == "thng", let refCount = u16(entry + 4), let refOffset = u16(entry + 6) else { continue }
            for r in 0...refCount {
                let ref = list + refOffset + r * 12
                guard let packed = u32(ref + 4), let length = u32(dataOffset + (packed & 0xFFFFFF)),
                      length >= 12,
                      let type = code(dataOffset + (packed & 0xFFFFFF) + 4),
                      let sub = code(dataOffset + (packed & 0xFFFFFF) + 8),
                      let manufacturer = code(dataOffset + (packed & 0xFFFFFF) + 12),
                      type.hasPrefix("au") else { continue }
                out.append(Component(type: type, subtype: sub, manufacturer: manufacturer))
            }
        }
        return out
    }
}
