// Port of src/AlsPatch.cs. Mac addition: Audio Units (`AuPluginInfo`) can be disabled too.
import Foundation

/// One third-party plugin of a set as a target for disabling — together with all its copies.
public struct AlsPluginSlot: Equatable, Hashable, Identifiable, Sendable {
    public var uid = ""
    public var name = ""
    public var kind: PluginKind = .vst3
    /// How many times it occurs in the set.
    public var count = 1
    /// The developer — only when it really is the developer. For VST2 the browser path holds the
    /// folder the plugin lies in ("Eff", "Gen"), and showing that as a vendor is a lie (see
    /// `AlsFile.parseBrowserPath`).
    public var vendor = ""

    public init() {}

    public var id: String { uid }

    /// "VST3", "VST2" or "AU".
    public var format: String {
        switch kind {
        case .vst3: return "VST3"
        case .vst2: return "VST2"
        default: return "AU"
        }
    }
}

/// A copy of a set in which Live does not recognise the chosen plugins.
///
/// A plugin in an .als is identified by an identifier, not by a name and not by a file:
///
///     <Vst3PluginInfo>…<Uid><Fields.0 Value="-1412567295" />…</Uid>
///     <VstPluginInfo><Path Value="…/Serum.vst" /><UniqueId Value="1483109208" />
///     <AuPluginInfo><ComponentType …/><ComponentSubType …/><ComponentManufacturer …/>
///
/// We substitute exactly those values — and Live honestly says "plugin not found", shows a
/// placeholder with the former name in its place, and loads the rest of the set. Nothing is
/// deleted: the device node, its place in the chain, the automation, the identifiers and the
/// saved preset blob all stay byte for byte. Cutting a plugin out of an .als means touching
/// DeviceChain, automation and IDs at once, and such an edit breaks a set more reliably than the
/// broken plugin itself.
///
/// The edit is surgical: only those values change, everything else is copied byte for byte. The
/// original is never opened for writing — we write into a separate file that the caller deletes.
///
/// We go as a stream, line by line, holding only the current device node in memory: one set
/// unpacks to 177 MB of XML.
public enum AlsPatch {
    /// The marker put in place of Fields.0 for VST3: "Aliv" in ASCII. It replaces only the high
    /// word while the other three fields stay as they were, so two disabled plugins do not
    /// collapse into one and the same non-existent identifier.
    static let marker: Int32 = 0x416C_6976

    /// What gets appended to a VST2's plugin path. A broken UniqueId alone is not enough: Live
    /// can also raise a VST2 by its file, and the plugin would then load as if nothing had
    /// happened — the probe would have checked nothing.
    static let disabledSuffix = ".alive-disabled"

    // MARK: targets

    /// The set's third-party plugins that can be disabled — one per identifier. Without an
    /// identifier a plugin cannot be addressed and does not get in here.
    public static func targets(_ info: AlsInfo?) -> [AlsPluginSlot] {
        guard let info else { return [] }
        var list: [AlsPluginSlot] = []
        var byUid: [String: Int] = [:]
        for p in info.plugins where !p.uid.isEmpty && p.kind != .maxForLive {
            let key = p.uid.lowercased()
            if let i = byUid[key] { list[i].count += 1; continue }
            var slot = AlsPluginSlot()
            slot.uid = p.uid
            slot.name = p.name
            slot.vendor = p.vendorConfident ? p.manufacturer : ""
            slot.kind = p.kind
            byUid[key] = list.count
            list.append(slot)
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// How many of the set's plugins cannot be disabled — nothing to identify them by.
    public static func unaddressable(_ info: AlsInfo?) -> Int {
        info?.plugins.filter { $0.uid.isEmpty }.count ?? 0
    }

    // MARK: patching

    private struct NodeKind {
        let open: [UInt8], close: [UInt8], kind: PluginKind
    }

    // The order matters: "<Vst3PluginInfo" is not a prefix of "<VstPluginInfo", but check VST3
    // first anyway.
    private static let nodeKinds = [
        NodeKind(open: Array("<Vst3PluginInfo".utf8), close: Array("</Vst3PluginInfo>".utf8), kind: .vst3),
        NodeKind(open: Array("<VstPluginInfo".utf8), close: Array("</VstPluginInfo>".utf8), kind: .vst2),
        NodeKind(open: Array("<AuPluginInfo".utf8), close: Array("</AuPluginInfo>".utf8), kind: .audioUnit),
    ]

    /// Writes a copy of `src` into `dst` with the listed plugins anonymised. Returns how many
    /// device nodes were touched — zero means none of the requested plugins was found in the
    /// file, and running such a probe is pointless.
    ///
    /// `inventory` is needed only so that a substituted identifier does not accidentally
    /// coincide with another installed plugin: Live would then silently put a foreign device in
    /// its place. On failure the partial `dst` is removed.
    @discardableResult
    public static func neutralize(src: String, dst: String, uids: [String],
                                  inventory: PluginInventory? = nil,
                                  isCancelled: () -> Bool = { false }) throws -> Int {
        guard !uids.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        let wanted = Set(uids.map { $0.lowercased() })
        var patched = 0
        var ok = false
        defer { if !ok { try? FileManager.default.removeItem(atPath: dst) } }

        let reader = try GzipLineReader(path: src)
        let writer = try GzipLineWriter(path: dst)
        var node: [UInt8]?
        var current = nodeKinds[0]

        while let line = try reader.next() {
            if isCancelled() { throw CancellationError() }
            if node == nil {
                guard let kind = opens(line) else { try writer.write(line); continue }
                current = kind
                node = line
            } else {
                node?.append(contentsOf: line)
            }
            // The closing tag is looked for in the current line rather than in everything
            // accumulated: otherwise the whole node would be rescanned for each of its lines.
            guard ByteSearch.contains(current.close, in: line) else { continue }

            let bytes = node ?? []
            node = nil
            let text = String(decoding: bytes, as: UTF8.self)
            if let uid = uidOf(text, kind: current.kind), wanted.contains(uid.lowercased()) {
                try writer.write(rewrite(text, kind: current.kind, inventory: inventory))
                patched += 1
            } else {
                try writer.write(bytes)          // untouched nodes keep their exact bytes
            }
        }
        // The file ended mid-node — write it as is so the tail is not lost.
        if let node { try writer.write(node) }
        try writer.finish()
        ok = true
        Diag.info("rescue: patched \(patched) device(s) in \((dst as NSString).lastPathComponent)")
        return patched
    }

    /// Whether a line opens a plugin description node. Plain substring search rather than XML
    /// parsing: the file is machine-written, these nodes do not nest in each other, and
    /// rebuilding the document through an XML writer would rewrite bytes the edit does not touch.
    /// The search cannot stray into the ProcessorState/Buffer blobs: those hold hexadecimal
    /// digits only. A self-closing node is skipped (it has no identifier to change).
    private static func opens(_ line: [UInt8]) -> NodeKind? {
        for k in nodeKinds {
            guard let at = ByteSearch.find(k.open, in: line) else { continue }
            let after = at + k.open.count
            guard after < line.count else { continue }
            let c = line[after]
            guard c == 0x20 || c == 0x3E || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x2F else { continue }
            if let close = line[after...].firstIndex(of: 0x3E), line[close - 1] == 0x2F { continue }
            return k
        }
        return nil
    }

    // MARK: identifying a plugin

    /// The identifier out of a node — in the same shape `AlsFile` and Live's own database use,
    /// computed by the same `PluginRef.finishUid` so the formula lives in one place: were the two
    /// parsers to drift apart, they would disable a plugin other than the one that was shown.
    static func uidOf(_ node: String, kind: PluginKind) -> String? {
        var ref = PluginRef(kind: kind)
        switch kind {
        case .vst2:
            guard let id = firstLong(node, "<UniqueId Value=\"") else { return nil }
            ref.vst2UniqueId = id
        case .audioUnit:
            guard let t = firstLong(node, "<ComponentType Value=\""),
                  let s = firstLong(node, "<ComponentSubType Value=\""),
                  let m = firstLong(node, "<ComponentManufacturer Value=\"") else { return nil }
            ref.auType = UInt32(truncatingIfNeeded: t)
            ref.auSubType = UInt32(truncatingIfNeeded: s)
            ref.auManufacturer = UInt32(truncatingIfNeeded: m)
        case .vst3:
            // A VST3 node holds two <Uid> blocks — one for the preset and one for the device,
            // with equal values. We take the last: the one sitting directly in Vst3PluginInfo,
            // exactly as AlsFile reads it.
            guard let block = lastUidBlock(node) else { return nil }
            for i in 0..<4 {
                guard let f = firstLong(block, "<Fields.\(i) Value=\"") else { return nil }
                ref.vst3Fields[i] = Int32(truncatingIfNeeded: f)
                ref.vst3FieldCount += 1
            }
        case .maxForLive: return nil
        }
        ref.finishUid()
        return ref.uid.isEmpty ? nil : ref.uid
    }

    private static func lastUidBlock(_ node: String) -> String? {
        guard let last = node.range(of: "<Uid>", options: .backwards),
              let close = node.range(of: "</Uid>", range: last.lowerBound..<node.endIndex) else { return nil }
        return String(node[last.lowerBound..<close.lowerBound])
    }

    // MARK: substitution

    private static func rewrite(_ node: String, kind: PluginKind, inventory: PluginInventory?) -> String {
        switch kind {
        case .vst2:
            guard let id = firstLong(node, "<UniqueId Value=\"") else { return node }
            let fake = freeVst2Id(Int32(truncatingIfNeeded: id), inventory)
            return suffixPaths(replaceAll(node, "<UniqueId Value=\"", String(fake)))
        case .audioUnit:
            return rewriteAu(node, inventory)
        default:
            let m = freeVst3Marker(node, inventory)
            return replaceAll(node, "<Fields.0 Value=\"", String(m))
        }
    }

    /// A marker that resembles nothing installed. Not paranoia: should a substituted identifier
    /// coincide with another plugin, Live would not say "not found" but put a foreign device in
    /// its place, and the probe would show an untruth.
    private static func freeVst3Marker(_ node: String, _ inventory: PluginInventory?) -> Int32 {
        guard let block = lastUidBlock(node) else { return marker }
        var probe = PluginRef(kind: .vst3)
        for i in 1..<4 {
            guard let f = firstLong(block, "<Fields.\(i) Value=\"") else { return marker }
            probe.vst3Fields[i] = Int32(truncatingIfNeeded: f)
        }
        probe.vst3FieldCount = 4
        for bump in Int32(0)..<64 {
            let candidate = marker &+ bump
            probe.vst3Fields[0] = candidate
            probe.finishUid()
            if inventory?.byUid(probe.uid) == nil { return candidate }
        }
        return marker
    }

    private static func freeVst2Id(_ original: Int32, _ inventory: PluginInventory?) -> Int32 {
        for bump in Int32(0)..<64 {
            let candidate = original ^ (marker &+ bump)
            if candidate == original { continue }
            if inventory?.byUid("vst2:\(candidate)") == nil { return candidate }
        }
        return original ^ marker
    }

    /// An Audio Unit is found by its component triple (type, subtype, manufacturer): the subtype
    /// and manufacturer codes are spoiled with the marker, the type (aumf/aumu/aufx) stays.
    private static func rewriteAu(_ node: String, _ inventory: PluginInventory?) -> String {
        guard let t = firstLong(node, "<ComponentType Value=\""),
              let s = firstLong(node, "<ComponentSubType Value=\""),
              let m = firstLong(node, "<ComponentManufacturer Value=\"") else { return node }
        let signed = node.contains("<ComponentSubType Value=\"-")
        func text(_ v: UInt32) -> String { signed ? String(Int32(bitPattern: v)) : String(v) }

        let mark = UInt32(bitPattern: marker)
        var sub = UInt32(truncatingIfNeeded: s) ^ mark, man = UInt32(truncatingIfNeeded: m) ^ mark
        for bump in UInt32(0)..<64 {
            var probe = PluginRef(kind: .audioUnit)
            probe.auType = UInt32(truncatingIfNeeded: t)
            probe.auSubType = UInt32(truncatingIfNeeded: s) ^ (mark &+ bump)
            probe.auManufacturer = UInt32(truncatingIfNeeded: m) ^ (mark &+ bump)
            probe.finishUid()
            if inventory?.byUid(probe.uid) == nil {
                sub = probe.auSubType ?? sub
                man = probe.auManufacturer ?? man
                break
            }
        }
        let a = replaceAll(node, "<ComponentSubType Value=\"", text(sub))
        return replaceAll(a, "<ComponentManufacturer Value=\"", text(man))
    }

    /// Appends ".alive-disabled" to every path in the node — no file by that name exists.
    private static func suffixPaths(_ node: String) -> String {
        let tag = "<Path Value=\""
        var out = ""
        var rest = node[...]
        while let at = rest.range(of: tag), let close = rest[at.upperBound...].firstIndex(of: "\"") {
            out += rest[..<close]
            out += disabledSuffix
            rest = rest[close...]
        }
        return out + rest
    }

    /// Replaces an attribute value in every occurrence of a tag inside the node.
    static func replaceAll(_ node: String, _ tag: String, _ value: String) -> String {
        var out = ""
        var rest = node[...]
        while let at = rest.range(of: tag), let close = rest[at.upperBound...].firstIndex(of: "\"") {
            out += rest[..<at.upperBound]
            out += value
            rest = rest[close...]
        }
        return out + rest
    }

    static func firstLong(_ s: String, _ tag: String) -> Int64? {
        guard let at = s.range(of: tag), let close = s[at.upperBound...].firstIndex(of: "\"") else { return nil }
        return Int64(s[at.upperBound..<close])
    }
}
