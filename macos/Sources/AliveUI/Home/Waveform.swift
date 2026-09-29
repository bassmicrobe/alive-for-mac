// Port of the Waveform / WaveReader envelope in src/AudioPlayer.cs. Upstream parses RIFF/AIFF by
// hand and falls back to Media Foundation; here AVAudioFile decodes everything it can open.
import Accelerate
import AVFoundation
import Foundation
import AliveCore

/// The envelope: the minimum and maximum of the signal in each column of the picture.
struct Waveform: Equatable, Sendable {
    var min: [Float] = []
    var max: [Float] = []
    var ok = false
    var duration: TimeInterval = 0

    static let failed = Waveform()
    var buckets: Int { max.count }
}

/// Splits a run of frames into the pieces that fall into one envelope column each, so a block of
/// audio is reduced with a few vector operations instead of a division per frame.
enum BucketSegments {
    /// First frame of column `bucket`: the smallest frame `f` with `f * buckets / total == bucket`.
    static func start(of bucket: Int, buckets: Int, total: Int64) -> Int64 {
        (Int64(bucket) * total + Int64(buckets) - 1) / Int64(buckets)
    }

    /// Calls `body(bucket, offset, length)` for every non-empty piece of the block of `count`
    /// frames that begins at absolute frame `frame`; `offset` is relative to the block.
    static func forEach(frame: Int64, count: Int, total: Int64, buckets: Int,
                        _ body: (_ bucket: Int, _ offset: Int, _ length: Int) -> Void) {
        guard count > 0, total > 0, buckets > 0 else { return }
        let end = frame + Int64(count)
        var bucket = Swift.min(buckets - 1, Int(frame * Int64(buckets) / total))
        var cursor = frame
        while cursor < end, bucket < buckets {
            let bucketEnd = bucket == buckets - 1 ? Int64.max : start(of: bucket + 1, buckets: buckets, total: total)
            let stop = Swift.min(end, bucketEnd)
            if stop > cursor { body(bucket, Int(cursor - frame), Int(stop - cursor)) }
            cursor = Swift.max(cursor, stop)
            bucket += 1
        }
    }
}

/// A few finished envelopes, so stepping back and forth through the renders of a set does not
/// decode the same files again. Keyed by what the file looked like when it was read.
final class WaveformCache: @unchecked Sendable {
    static let shared = WaveformCache(capacity: 24)

    private let lock = NSLock()
    private let capacity: Int
    private var entries: [String: Waveform] = [:]
    private var order: [String] = []

    init(capacity: Int) { self.capacity = capacity }

    static func key(path: String, buckets: Int) -> String? {
        guard let st = FileStat.of(path) else { return nil }
        return "\(path)|\(st.size)|\(st.modified.timeIntervalSinceReferenceDate)|\(buckets)"
    }

    func get(_ key: String) -> Waveform? {
        lock.lock(); defer { lock.unlock() }
        return entries[key]
    }

    func put(_ key: String, _ wave: Waveform) {
        lock.lock(); defer { lock.unlock() }
        if entries[key] == nil { order.append(key) }
        entries[key] = wave
        while order.count > capacity { entries[order.removeFirst()] = nil }
    }
}

enum WaveformReader {
    static let minBuckets = 16
    /// Frames decoded per read: the whole file never sits in memory.
    static let chunkFrames: AVAudioFrameCount = 65_536

    /// Envelope of the file in `buckets` columns. Blocking (reads the whole file): call it from
    /// a background task. `isCancelled` is polled between chunks.
    static func read(path: String, buckets requested: Int, isCancelled: () -> Bool = { false }) -> Waveform {
        let buckets = Swift.max(minBuckets, requested)
        let cacheKey = WaveformCache.key(path: path, buckets: buckets)
        if let cacheKey, let hit = WaveformCache.shared.get(cacheKey) { return hit }
        let wave = decode(path: path, buckets: buckets, isCancelled: isCancelled)
        if wave.ok, let cacheKey { WaveformCache.shared.put(cacheKey, wave) }
        return wave
    }

    private static func decode(path: String, buckets: Int, isCancelled: () -> Bool) -> Waveform {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames)
        else { return .failed }

        let total = file.length
        let rate = file.processingFormat.sampleRate
        guard total > 0, rate > 0 else { return .failed }

        var lo = [Float](repeating: 0, count: buckets)
        var hi = [Float](repeating: 0, count: buckets)
        var seen = [Bool](repeating: false, count: buckets)
        var frame: AVAudioFramePosition = 0
        let channels = Int(file.processingFormat.channelCount)

        while frame < total {
            if isCancelled() { return .failed }
            do { try file.read(into: buffer, frameCount: chunkFrames) } catch { break }
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let data = buffer.floatChannelData else { return .failed }
            BucketSegments.forEach(frame: frame, count: n, total: total, buckets: buckets) { bucket, offset, length in
                var mn = Float.greatestFiniteMagnitude, mx = -Float.greatestFiniteMagnitude
                for c in 0..<channels {
                    var cmin: Float = 0, cmax: Float = 0
                    vDSP_minv(data[c] + offset, 1, &cmin, vDSP_Length(length))
                    vDSP_maxv(data[c] + offset, 1, &cmax, vDSP_Length(length))
                    mn = Swift.min(mn, cmin)
                    mx = Swift.max(mx, cmax)
                }
                if !seen[bucket] { lo[bucket] = mn; hi[bucket] = mx; seen[bucket] = true } else {
                    lo[bucket] = Swift.min(lo[bucket], mn)
                    hi[bucket] = Swift.max(hi[bucket], mx)
                }
            }
            frame += AVAudioFramePosition(n)
        }
        guard frame > 0 else { return .failed }
        // Columns the read never reached (a truncated file) stay flat.
        return Waveform(min: lo.map { Swift.max(-1, Swift.min(0, $0)) }, max: hi.map { Swift.min(1, Swift.max(0, $0)) },
                        ok: true, duration: Double(total) / rate)
    }
}
