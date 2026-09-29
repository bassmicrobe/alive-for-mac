// Port of the wave and format reading of DetailPanel.LoadWave (src/DetailPanel.cs) — AVFoundation
// instead of Media Foundation. Runs off the main thread.
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
    /// for the picture. Never throws: what could not be read is left out.
    static func load(path: String, canPreview: Bool, size: Int64, buckets: Int) -> SampleInfo {
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
        info.wave = peaks(of: file, buckets: buckets).map(SampleInfo.Wave.peaks) ?? .unavailable
        return info
    }

    private static func peaks(of file: AVAudioFile, buckets: Int) -> [Float]? {
        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: readChunk) else { return nil }
        var wave = WavePeaks(totalFrames: file.length, buckets: buckets)
        let channels = Int(file.processingFormat.channelCount)
        do {
            while file.framePosition < file.length {
                try file.read(into: buffer, frameCount: readChunk)
                let frames = Int(buffer.frameLength)
                guard frames > 0, let data = buffer.floatChannelData else { break }
                let views = (0..<channels).map { UnsafeBufferPointer(start: data[$0], count: frames) }
                wave.add(channels: views, frames: frames)
            }
        } catch {
            Diag.info("samples: wave: \((file.url.path as NSString).lastPathComponent): \(error.localizedDescription)")
            return nil
        }
        return wave.peaks
    }
}
