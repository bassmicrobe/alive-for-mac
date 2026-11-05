// Port of SampleIndex.LoadCache / SaveCache (src/SampleIndex.cs): samples.cache in upstream's format.
import Foundation

/// Layout (little-endian, .NET BinaryWriter strings): version, folders (path, parent, samples,
/// bytes, created, modified), files (folder, name, size, silent, created, modified, print), roots.
/// Version 2 has neither dates nor prints; it is still read, so the first walk after an update
/// keeps the AIFF flags instead of opening every AIFF again.
public enum SampleCache {
    static let version: Int32 = 4
    private static let oldVersion: Int32 = 2
    private static let minFolderBytes = 17   // path string (1) + parent (4) + samples (4) + bytes (8); v2 has no dates
    private static let minFileBytes = 14     // folder (4) + name (1) + size (8) + silent (1)

    public static func path(dir: String) -> String { AppHome.file("samples.cache", in: dir) }

    /// The cached index, or `SampleIndex.empty` when there is none or it is unreadable.
    public static func load(dir: String) -> SampleIndex {
        guard let data = FileManager.default.contents(atPath: path(dir: dir)) else { return .empty }
        do { return try decode(data) } catch {
            Diag.fail("samples.cache unreadable, will rescan", error)
            return .empty
        }
    }

    /// The cache is not critical — the worst case is walking again — but a failure is logged.
    /// `walked` is when the walk behind `index` ended; it is written behind the roots (see
    /// `walkedAt`). A walk that did not cover every root passes `.distantPast`, so `walkDue` is
    /// true at the next start.
    public static func save(_ index: SampleIndex, dir: String, walked: Date = Date()) {
        var data = encode(index)
        data.append(walkTail(walked))
        do { try AppHome.writeAtomically(data, to: path(dir: dir)) } catch {
            Diag.fail("samples.cache write", error)
        }
    }

    // MARK: when it was walked

    /// A mark and the time of the walk (UTC ticks) after the roots — twelve bytes the decoder
    /// does not reach, so the version stays and a copy of Alive from before reads the file as
    /// ever. Upstream takes the file's modification time for this (a6c8dc1 `WalkedUtc`); the mark
    /// keeps the answer when a backup tool, a copy or a restore touches the file.
    static let walkMark: Int32 = 0x6B6C6177      // "walk"
    private static let tailBytes = 12

    private static func walkTail(_ walked: Date) -> Data {
        var w = DotNetWriter()
        w.int32(walkMark)
        w.int64(DotNetTicks.utc(walked))
        return w.data
    }

    /// When the last whole walk ended: nil without a cache. A cache written before the walk time
    /// was kept is taken by its modification time, like upstream — only a walk writes it.
    public static func walkedAt(dir: String) -> Date? {
        let file = path(dir: dir)
        guard let stat = FileStat.of(file) else { return nil }
        if let marked = markedWalk(file, size: stat.size) { return marked }
        return stat.modified
    }

    private static func markedWalk(_ file: String, size: Int64) -> Date? {
        guard size >= Int64(tailBytes), let h = FileHandle(forReadingAtPath: file) else { return nil }
        defer { try? h.close() }
        do {
            try h.seek(toOffset: UInt64(size) - UInt64(tailBytes))
            guard let tail = try h.read(upToCount: tailBytes), tail.count == tailBytes else { return nil }
            var r = DotNetReader(tail)
            guard try r.int32() == walkMark else { return nil }
            let ticks = try r.int64()
            return DotNetTicks.isValid(ticks: ticks) ? DotNetTicks.date(utc: ticks) : nil
        } catch {
            return nil
        }
    }

    static func encode(_ index: SampleIndex) -> Data {
        var w = DotNetWriter()
        w.int32(version)
        w.int32(Int32(clamping: index.folders.count))
        for f in index.folders {
            w.string(f.path)
            w.int32(Int32(clamping: f.parent ?? -1))
            w.int32(Int32(clamping: f.totalSamples))
            w.int64(f.totalBytes)
            w.int64(ticks(f.created))
            w.int64(ticks(f.modified))
        }
        w.int32(Int32(clamping: index.files.count))
        for s in index.files {
            w.int32(Int32(clamping: s.folder))
            w.string(s.name)
            w.int64(s.size)
            w.bool(s.silent)
            w.int64(ticks(s.created))
            w.int64(ticks(s.modified))
            w.int64(Int64(bitPattern: s.print))
        }
        w.int32(Int32(clamping: index.roots.count))
        for r in index.roots { w.int32(Int32(clamping: r)) }
        return w.data
    }

    static func decode(_ data: Data) throws -> SampleIndex {
        var r = DotNetReader(data)
        let v = try r.int32()
        guard v == version || v == oldVersion else { return .empty }
        let dates = v == version
        var idx = SampleIndex()

        // A count from the file is checked against the bytes left (a folder takes at least 33,
        // a file 5+, a root 4) and never used to reserve memory: a damaged cache must fall
        // back to a rescan, not crash the launch.
        let folders = Int(try r.int32())
        guard folders >= 0, folders <= r.remaining / minFolderBytes else { throw BinaryFormatError.truncated }
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
        guard files >= 0, files <= r.remaining / minFileBytes else { throw BinaryFormatError.truncated }
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
        guard roots >= 0, roots <= r.remaining / 4 else { throw BinaryFormatError.truncated }
        for _ in 0..<roots {
            let root = Int(try r.int32())
            guard root >= 0, root < idx.folders.count else { throw BinaryFormatError.truncated }
            idx.roots.append(root)
        }
        return idx
    }

    private static func ticks(_ d: Date?) -> Int64 { d.map(DotNetTicks.utc) ?? 0 }

    private static func date(_ ticks: Int64) -> Date? {
        ticks > 0 && DotNetTicks.isValid(ticks: ticks) ? DotNetTicks.date(utc: ticks) : nil
    }
}

extension SampleIndex {
    /// How old a whole walk may be before a start walks the library again.
    public static let walkValidity: TimeInterval = 24 * 3600

    /// Whether a start has to walk the library: the last whole walk is over a day old (or has no
    /// date, or lies a day in the future — the clock was set back), or the cache lacks a folder
    /// that is switched on now. It walked on every start — 41 s on 190 thousand samples from a
    /// cold disk, the first start after a reboot, fighting Live for that disk while it loaded a
    /// set. A manual rescan and a newly added folder still walk at once (upstream a6c8dc1
    /// `WalkDue`).
    public static func walkDue(cached: SampleIndex, roots: [String], disabled: [String],
                               walkedAt: Date?, now: Date = Date()) -> Bool {
        guard let walkedAt, abs(now.timeIntervalSince(walkedAt)) <= walkValidity else { return true }
        let have = cached.roots.map { norm(cached.folders[$0].path).lowercased() }
        return effective(roots, disabled: disabled).contains { !have.contains(norm($0).lowercased()) }
    }
}
