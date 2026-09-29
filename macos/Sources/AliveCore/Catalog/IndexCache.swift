// Port of src/ProjectIndex.cs (LoadCache / SaveCache): index.cache in .NET BinaryWriter layout
import Foundation

/// The on-disk cache of parsed sets. Format v11 (upstream's): int32 version, int32 count, then per
/// set the fields below; strings are 7-bit-length-prefixed UTF-8, dates are UTC ticks.
enum IndexCache {
    static let version: Int32 = 11   // 11: the paths and sizes of the samples a set plays

    static func path(dir: String) -> String { AppHome.file("index.cache", in: dir) }

    /// Keyed by lowercased path. A missing, foreign-version or damaged cache reads as empty.
    static func load(dir: String) -> [String: SetEntry] {
        guard let data = FileManager.default.contents(atPath: path(dir: dir)) else { return [:] }
        var r = DotNetReader(data)
        var map: [String: SetEntry] = [:]
        do {
            guard try r.int32() == version else { return [:] }
            let n = Int(try r.int32())
            guard n >= 0 else { return [:] }
            for _ in 0..<n {
                let e = try readEntry(&r)
                map[e.path.lowercased()] = e
            }
        } catch {
            Diag.warn("index.cache unreadable, rescanning: \(error)")
            return [:]
        }
        return map
    }

    private static func readEntry(_ r: inout DotNetReader) throws -> SetEntry {
        var e = SetEntry()
        e.path = try r.string()
        e.name = try r.string()
        e.projectName = try r.string()
        e.modified = DotNetTicks.date(utc: try r.int64())
        e.created = DotNetTicks.date(utc: try r.int64())
        e.size = try r.int64()
        e.isBackup = try r.bool()
        e.creator = try r.string()
        e.tempo = try r.double()
        e.key = try r.string()
        e.scaleRoot = Int(try r.int32())
        e.scaleIndex = Int(try r.int32())
        e.tracks = Int(try r.int32())
        e.missingFiles = Int(try r.int32())
        e.totalRefs = Int(try r.int32())
        e.error = try r.string()
        let pc = Int(try r.int32())
        guard pc >= 0 else { throw BinaryFormatError.truncated }
        for _ in 0..<pc {
            e.plugins.append(try r.string())
            e.pluginVendors.append(try r.string())
            e.pluginVendorConfident.append(try r.bool())
            e.pluginUids.append(try r.string())
        }
        let sc = Int(try r.int32())
        guard sc >= 0 else { throw BinaryFormatError.truncated }
        for _ in 0..<sc {
            e.samples.append(try r.string())
            e.sampleSizes.append(try r.int64())
        }
        return e
    }

    /// Atomic (temp file + rename); the cache is not critical — the worst case is a rescan — but
    /// a failure is logged.
    static func save(_ sets: [SetEntry], dir: String) {
        var w = DotNetWriter()
        w.int32(version)
        w.int32(Int32(sets.count))
        for e in sets { write(e, to: &w) }
        do { try AppHome.writeAtomically(w.data, to: path(dir: dir)) } catch { Diag.fail("index.cache write", error) }
    }

    private static func write(_ e: SetEntry, to w: inout DotNetWriter) {
        w.string(e.path); w.string(e.name); w.string(e.projectName)
        w.int64(DotNetTicks.utc(e.modified)); w.int64(DotNetTicks.utc(e.created))
        w.int64(e.size); w.bool(e.isBackup)
        w.string(e.creator); w.double(e.tempo); w.string(e.key)
        w.int32(Int32(e.scaleRoot)); w.int32(Int32(e.scaleIndex)); w.int32(Int32(e.tracks))
        w.int32(Int32(e.missingFiles)); w.int32(Int32(e.totalRefs)); w.string(e.error)
        w.int32(Int32(e.plugins.count))
        for i in e.plugins.indices {
            w.string(e.plugins[i])
            w.string(i < e.pluginVendors.count ? e.pluginVendors[i] : "")
            w.bool(i < e.pluginVendorConfident.count && e.pluginVendorConfident[i])
            w.string(i < e.pluginUids.count ? e.pluginUids[i] : "")
        }
        w.int32(Int32(e.samples.count))
        for i in e.samples.indices {
            w.string(e.samples[i])
            w.int64(i < e.sampleSizes.count ? e.sampleSizes[i] : 0)
        }
    }
}
