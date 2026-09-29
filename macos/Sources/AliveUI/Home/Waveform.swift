// Port of the Waveform / WaveReader envelope in src/AudioPlayer.cs. Upstream parses RIFF/AIFF by
// hand and falls back to Media Foundation; here AVAudioFile decodes everything it can open.
import AVFoundation
import Foundation

/// The envelope: the minimum and maximum of the signal in each column of the picture.
struct Waveform: Equatable, Sendable {
    var min: [Float] = []
    var max: [Float] = []
    var ok = false
    var duration: TimeInterval = 0

    static let failed = Waveform()
    var buckets: Int { max.count }
}

enum WaveformReader {
    static let minBuckets = 16
    /// Frames decoded per read: the whole file never sits in memory.
    static let chunkFrames: AVAudioFrameCount = 65_536

    /// Envelope of the file in `buckets` columns. Blocking (reads the whole file): call it from
    /// a background task. `isCancelled` is polled between chunks.
    static func read(path: String, buckets requested: Int, isCancelled: () -> Bool = { false }) -> Waveform {
        let buckets = Swift.max(minBuckets, requested)
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
            for i in 0..<n {
                let bucket = Swift.min(buckets - 1, Int((frame + AVAudioFramePosition(i)) * AVAudioFramePosition(buckets) / total))
                var mn = Float.greatestFiniteMagnitude, mx = -Float.greatestFiniteMagnitude
                for c in 0..<channels {
                    let v = data[c][i]
                    mn = Swift.min(mn, v)
                    mx = Swift.max(mx, v)
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
