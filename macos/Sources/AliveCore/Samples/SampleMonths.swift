// Port of DetailPanel.CountMonths (src/DetailPanel.cs) and SamplesTab.SampleFoldersOf (src/SamplesTab.cs);
// WavePeaks is Mac-only (upstream's WaveReader decodes through Media Foundation).
import Foundation

/// How many projects saved a set that uses something, month by month — what the usage chart draws.
/// A project counts once a month however many of its sets were saved then. The window ends at this
/// month and reaches back to the first use, a year at least and four at most: past that a column
/// would be too thin to read, and the older use is still in the projects list.
public struct SampleMonths: Equatable, Sendable {
    /// Oldest first; the last entry is `now`'s month. Empty — nothing to draw.
    public var counts: [Int] = []
    /// First day of the month of `counts[0]`.
    public var from = Date.distantPast

    public static let empty = SampleMonths()

    public static func count(_ sets: [SetEntry], now: Date = Date(), calendar: Calendar = .current) -> SampleMonths {
        func key(_ d: Date) -> Int {
            let c = calendar.dateComponents([.year, .month], from: d)
            return (c.year ?? 0) * 12 + (c.month ?? 1) - 1
        }
        let last = key(now)
        var first = last
        var byMonth: [Int: Set<String>] = [:]
        for s in sets where s.modified > .distantPast {
            let k = key(s.modified)
            if k > last || k <= last - 48 { continue }
            byMonth[k, default: []].insert(s.projectDir.lowercased())
            first = min(first, k)
        }
        guard !byMonth.isEmpty else { return .empty }
        first = min(first, last - 11)
        var out = SampleMonths()
        out.counts = [Int](repeating: 0, count: last - first + 1)
        for (k, projects) in byMonth { out.counts[k - first] = projects.count }
        var c = DateComponents()
        c.year = first / 12
        c.month = first % 12 + 1
        c.day = 1
        out.from = calendar.date(from: c) ?? .distantPast
        return out
    }
}

extension SampleUsage {
    /// The library folders a set takes samples from, the most first — for its panel on the Sets tab.
    /// A sample counts under the folder right below its root: a pack, or a vendor's folder of
    /// packs, as the library is laid out.
    public func folders(ofSet path: String, in index: SampleIndex) -> [(folder: Int, count: Int)] {
        var n: [Int: Int] = [:]
        for f in files(ofSet: path) where f < index.files.count {
            n[index.packFolder(of: index.files[f].folder), default: 0] += 1
        }
        return n.map { (folder: $0.key, count: $0.value) }.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return index.folders[a.folder].name.localizedStandardCompare(index.folders[b.folder].name) == .orderedAscending
        }
    }
}

/// Peak per bucket of a sound, 0...1 — the picture of a sample. Fed in blocks of interleaved or
/// per-channel frames as a decoder produces them.
public struct WavePeaks: Sendable {
    public private(set) var peaks: [Float]
    private let totalFrames: Int64
    private var frame: Int64 = 0

    public init(totalFrames: Int64, buckets: Int) {
        self.totalFrames = max(1, totalFrames)
        peaks = [Float](repeating: 0, count: max(1, buckets))
    }

    /// One block: `channels` arrays of equal length (deinterleaved, as AVAudioPCMBuffer gives them).
    public mutating func add(channels: [UnsafeBufferPointer<Float>], frames: Int) {
        for i in 0..<frames {
            var m: Float = 0
            for ch in channels { m = max(m, abs(ch[i])) }
            let b = min(peaks.count - 1, Int((frame + Int64(i)) * Int64(peaks.count) / totalFrames))
            if m > peaks[b] { peaks[b] = min(1, m) }
        }
        frame += Int64(frames)
    }
}
