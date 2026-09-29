// Port of the wave and format reading of DetailPanel.LoadWave (src/DetailPanel.cs) — AVFoundation
// instead of Media Foundation. Runs off the main thread.
import Accelerate
import Foundation
import AVFoundation
import AliveCore

/// What the panel shows about one sample: its format, length and picture.
struct SampleInfo: Equatable, Sendable {
    enum Wave: Equatable, Sendable {
        case reading
        case peaks([Float])
        /// Nothing to draw: only Live plays the file, or it would not decode.
        case unavailable
    }

    var path: String
    var format = ""
    var durationMs = 0
    var wave = Wave.reading
}

enum SampleInfoLoader {
    /// Beyond this a picture would mean decoding minutes of audio for a glance.
    static let maxWaveBytes: Int64 = 200 * 1024 * 1024
    private static let readChunk: AVAudioFrameCount = 1 << 16

    /// Header first (WAV and AIFF are read by hand and are quick); AVFoundation for the rest and
    /// for the picture. Never throws: what could not be read is left out. `isCancelled` is polled
    /// between chunks: a picture nobody waits for any more stops decoding (and reads `.unavailable`).
    static func load(path: String, canPreview: Bool, size: Int64, buckets: Int,
                     isCancelled: () -> Bool = { false }) -> SampleInfo {
        var info = SampleInfo(path: path)
        if let h = AudioFileInfo.header(path: path) {
            info.format = SampleFormat.format(h)
            info.durationMs = h.durationMs
        }
        guard canPreview, size <= maxWaveBytes else {
            info.wave = .unavailable
            return info
        }
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else {
            info.wave = .unavailable
            return info
        }
        let fmt = file.processingFormat
        if info.format.isEmpty {
            var h = AudioHeader()
            h.rate = Int(fmt.sampleRate)
            h.channels = Int(fmt.channelCount)
            info.format = SampleFormat.format(h)
        }
        if info.durationMs == 0, fmt.sampleRate > 0 {
            info.durationMs = Int(Double(file.length) * 1000 / fmt.sampleRate)
        }
        info.wave = peaks(of: file, buckets: buckets, isCancelled: isCancelled).map(SampleInfo.Wave.peaks) ?? .unavailable
        return info
    }

    /// Peak per column, 0...1: whole blocks are reduced with vector operations, one call per
    /// column and channel that the block touches.
    static func peaks(of file: AVAudioFile, buckets: Int, isCancelled: () -> Bool) -> [Float]? {
        let total = file.length
        guard total > 0, buckets > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: readChunk) else { return nil }
        var peaks = [Float](repeating: 0, count: buckets)
        let channels = Int(file.processingFormat.channelCount)
        var frame: Int64 = 0
        do {
            while file.framePosition < total {
                if isCancelled() { return nil }
                try file.read(into: buffer, frameCount: readChunk)
                let frames = Int(buffer.frameLength)
                guard frames > 0, let data = buffer.floatChannelData else { break }
                BucketSegments.forEach(frame: frame, count: frames, total: total, buckets: buckets) { bucket, offset, length in
                    for c in 0..<channels {
                        var m: Float = 0
                        vDSP_maxmgv(data[c] + offset, 1, &m, vDSP_Length(length))
                        if m > peaks[bucket] { peaks[bucket] = Swift.min(1, m) }
                    }
                }
                frame += Int64(frames)
            }
        } catch {
            Diag.info("samples: wave: \((file.url.path as NSString).lastPathComponent): \(error.localizedDescription)")
            return nil
        }
        return peaks
    }
}
