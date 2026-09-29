// Port of SampleIndex.LoadCache / SaveCache (src/SampleIndex.cs): samples.cache in upstream's format.
import Foundation

/// Layout (little-endian, .NET BinaryWriter strings): version, folders (path, parent, samples,
/// bytes, created, modified), files (folder, name, size, silent, created, modified, print), roots.
/// Version 2 has neither dates nor prints; it is still read, so the first walk after an update
/// keeps the AIFF flags instead of opening every AIFF again.
public enum SampleCache {
    static let version: Int32 = 4
    private static let oldVersion: Int32 = 2

    public static func path(dir: String) -> String { AppHome.file("samples.cache", in: dir) }

    /// The cached index, or `SampleIndex.empty` when there is none or it is unreadable.
    public static func load(dir: String) -> SampleIndex {
        guard let data = FileManager.default.contents(atPath: path(dir: dir)) else { return .empty }
        do { return try decode(data) } catch {
            Diag.fail("samples.cache read", error)
            return .empty
        }
    }

    /// The cache is not critical — the worst case is walking again — but a failure is logged.
    public static func save(_ index: SampleIndex, dir: String) {
        do { try AppHome.writeAtomically(encode(index), to: path(dir: dir)) } catch {
            Diag.fail("samples.cache write", error)
        }
    }

    static func encode(_ index: SampleIndex) -> Data {
        var w = DotNetWriter()
        w.int32(version)
        w.int32(Int32(index.folders.count))
        for f in index.folders {
            w.string(f.path)
            w.int32(Int32(f.parent ?? -1))
            w.int32(Int32(f.totalSamples))
            w.int64(f.totalBytes)
            w.int64(ticks(f.created))
            w.int64(ticks(f.modified))
        }
        w.int32(Int32(index.files.count))
        for s in index.files {
            w.int32(Int32(s.folder))
            w.string(s.name)
            w.int64(s.size)
            w.bool(s.silent)
            w.int64(ticks(s.created))
            w.int64(ticks(s.modified))
            w.int64(Int64(bitPattern: s.print))
        }
        w.int32(Int32(index.roots.count))
        for r in index.roots { w.int32(Int32(r)) }
        return w.data
    }

    static func decode(_ data: Data) throws -> SampleIndex {
        var r = DotNetReader(data)
        let v = try r.int32()
        guard v == version || v == oldVersion else { return .empty }
        let dates = v == version
        var idx = SampleIndex()

        let folders = Int(try r.int32())
        idx.folders.reserveCapacity(folders)
        for i in 0..<folders {
            var f = SampleFolder()
            f.path = try r.string()
            let parent = Int(try r.int32())
            f.totalSamples = Int(try r.int32())
            f.totalBytes = try r.int64()
            if dates {
                f.created = date(try r.int64())
                f.modified = date(try r.int64())
            }
            if parent >= 0 {
                guard parent < i else { throw BinaryFormatError.truncated }   // a parent is written first
                f.parent = parent
                f.name = (f.path as NSString).lastPathComponent
                idx.folders[parent].children.append(i)
            } else {
                f.name = f.path
            }
            idx.folders.append(f)
        }

        let files = Int(try r.int32())
        idx.files.reserveCapacity(files)
        for i in 0..<files {
            var s = SampleFile()
            s.folder = Int(try r.int32())
            guard s.folder >= 0, s.folder < idx.folders.count else { throw BinaryFormatError.truncated }
            s.name = try r.string()
            s.size = try r.int64()
            s.silent = try r.bool()
            if dates {
                s.created = date(try r.int64())
                s.modified = date(try r.int64())
                s.print = UInt64(bitPattern: try r.int64())
            }
            idx.folders[s.folder].files.append(i)
            idx.files.append(s)
        }

        let roots = Int(try r.int32())
        for _ in 0..<roots {
            let root = Int(try r.int32())
            guard root >= 0, root < idx.folders.count else { throw BinaryFormatError.truncated }
            idx.roots.append(root)
        }
        return idx
    }

    private static func ticks(_ d: Date?) -> Int64 { d.map(DotNetTicks.utc) ?? 0 }

    private static func date(_ ticks: Int64) -> Date? {
        ticks > 0 && ticks <= 3_155_378_975_999_999_999 ? DotNetTicks.date(utc: ticks) : nil
    }
}
