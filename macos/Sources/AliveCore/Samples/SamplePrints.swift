// Port of SampleIndex.TakePrints / Print (src/SampleIndex.cs)
import Foundation

/// Content hashes for the files that could be copies of each other — equal name and size (8,001 of
/// 180,378 on the upstream development machine), read whole once. A hash from the previous index
/// is kept while the file's size and date stay the same.
enum SamplePrints {
    /// Whole-file reads are disk-bound: a few in flight keep the disk busy, one per core only
    /// multiplies buffers and seeks.
    static let readers = 3

    static func take(_ idx: inout SampleIndex, known: [String: SampleFile], isCancelled: () -> Bool) {
        var groups: [String: [Int]] = [:]
        for (i, f) in idx.files.enumerated() {
            groups[String(f.size) + "|" + f.name.lowercased(), default: []].append(i)
        }
        var reused: [(Int, UInt64)] = []
        var todo: [Int] = []
        for g in groups.values where g.count > 1 {
            for i in g {
                let f = idx.files[i]
                if let was = known[idx.path(of: i).lowercased()], was.print != 0, was.size == f.size,
                   sameDate(was.modified, f.modified) {
                    reused.append((i, was.print))
                } else {
                    todo.append(i)
                }
            }
        }
        for (i, p) in reused { idx.files[i].print = p }

        let paths = todo.map { idx.path(of: $0) }
        let prints = Parallel.map(count: todo.count, workers: readers, isCancelled: isCancelled) { k in
            SamplePrints.print(path: paths[k])
        }
        for (k, i) in todo.enumerated() { idx.files[i].print = prints[k] ?? 0 }
    }

    private static func sameDate(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return DotNetTicks.sameInstant(x, y)
        default: return false
        }
    }

    /// FNV-1a over the whole file. A few blocks of it were tried first upstream and were not
    /// enough: the Dry and Wet takes of one guitar in one pack have the same silence at the start
    /// and the same tail, and part only in the middle. FNV rather than a cryptographic hash — no
    /// cryptography needed. 0 — the file would not open (a real hash of 0 becomes 1).
    static func print(path: String) -> UInt64 {
        guard let h = FileHandle(forReadingAtPath: path) else { return 0 }
        defer { try? h.close() }
        var hash: UInt64 = 14_695_981_039_346_656_037
        do {
            while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty {
                chunk.withUnsafeBytes { raw in
                    for b in raw { hash = (hash ^ UInt64(b)) &* 1_099_511_628_211 }
                }
            }
        } catch { return 0 }
        return hash == 0 ? 1 : hash
    }
}
