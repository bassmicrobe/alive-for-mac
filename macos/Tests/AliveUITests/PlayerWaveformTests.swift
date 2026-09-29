import AVFoundation
import XCTest
@testable import AliveCore
@testable import AliveUI

/// Every file here is silent or a known short pattern: nothing is ever played.
final class PlayerWaveformDecodingTests: XCTestCase {
    private var dir = ""

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "alive-wave-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: dir)
        super.tearDown()
    }

    /// 16-bit mono WAV of `samples` (or `frames` zeros).
    private func wav(_ name: String, samples: [Int16]? = nil, frames: Int = 0, rate: Int = 44100) throws -> String {
        func le(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        let count = samples?.count ?? frames
        var d = Array("RIFF".utf8) + le(36 + count * 2, 4) + Array("WAVE".utf8) + Array("fmt ".utf8) + le(16, 4)
        d += le(1, 2) + le(1, 2) + le(rate, 4) + le(rate * 2, 4) + le(2, 2) + le(16, 2)
        d += Array("data".utf8) + le(count * 2, 4)
        var data = Data(d)
        if let samples {
            for s in samples { data.append(contentsOf: le(Int(UInt16(bitPattern: s)), 2)) }
        } else {
            data.append(Data(count: count * 2))
        }
        let path = dir + "/" + name
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    func testSegmentsMatchThePerFrameBucketFormula() {
        for (total, buckets) in [(1000, 16), (10, 16), (65_537, 300), (7, 3), (100_000, 640)] {
            var seen = [Int](repeating: -1, count: total)
            // Blocks of an awkward size, like a decoder's reads.
            var frame = 0
            while frame < total {
                let n = min(4099, total - frame)
                BucketSegments.forEach(frame: Int64(frame), count: n, total: Int64(total), buckets: buckets) { b, off, len in
                    for i in 0..<len { seen[frame + off + i] = b }
                }
                frame += n
            }
            for f in 0..<total {
                XCTAssertEqual(seen[f], min(buckets - 1, f * buckets / total), "frame \(f) of \(total) in \(buckets)")
            }
        }
    }

    func testEnvelopeIsTheMinAndMaxOfEveryColumn() throws {
        // A ramp with a spike in the 3rd column of 16 and a dip in the 6th.
        let total = 16 * 1000
        var samples = (0..<total).map { Int16(($0 % 1000) - 500) }
        samples[2 * 1000 + 300] = 20_000
        samples[5 * 1000 + 10] = -30_000
        let path = try wav("ramp.wav", samples: samples)
        let w = WaveformReader.read(path: path, buckets: 16)
        XCTAssertTrue(w.ok)
        XCTAssertEqual(w.buckets, 16)
        XCTAssertEqual(w.max[2], Float(20_000) / 32768, accuracy: 1e-4)
        XCTAssertEqual(w.min[5], Float(-30_000) / 32768, accuracy: 1e-4)
        XCTAssertEqual(w.max[0], Float(499) / 32768, accuracy: 1e-4)
        XCTAssertEqual(w.min[0], Float(-500) / 32768, accuracy: 1e-4)
        XCTAssertEqual(w.duration, Double(total) / 44100, accuracy: 1e-6)
    }

    func testFinishedEnvelopesAreRememberedButNotForAChangedFile() throws {
        let path = try wav("a.wav", samples: (0..<3200).map { Int16($0 % 200) })
        let first = WaveformReader.read(path: path, buckets: 16)
        let key = try XCTUnwrap(WaveformCache.key(path: path, buckets: 16))
        XCTAssertNotNil(WaveformCache.shared.get(key))
        XCTAssertEqual(WaveformReader.read(path: path, buckets: 16), first)
        // Another length is another file: not served from the memory.
        _ = try wav("a.wav", samples: (0..<6400).map { Int16($0 % 200) })
        XCTAssertNotEqual(WaveformReader.read(path: path, buckets: 16).duration, first.duration)
    }

    func testACancelledReadStopsEarlyOnALongSilentFile() throws {
        // Two minutes of silence: about 80 chunks of 65536 frames.
        let path = try wav("long.wav", frames: 44100 * 120)
        var polls = 0
        let w = WaveformReader.read(path: path, buckets: 300, isCancelled: { polls += 1; return polls > 3 })
        XCTAssertFalse(w.ok, "a cancelled read is not a picture")
        XCTAssertEqual(polls, 4, "it stopped at the first check that said so, not at the end of the file")
        let key = try XCTUnwrap(WaveformCache.key(path: path, buckets: 300))
        XCTAssertNil(WaveformCache.shared.get(key))

        var uncancelled = 0
        let full = WaveformReader.read(path: path, buckets: 300, isCancelled: { uncancelled += 1; return false })
        XCTAssertTrue(full.ok)
        XCTAssertGreaterThan(uncancelled, 30)
    }

    func testSampleInfoStopsEarlyToo() throws {
        let path = try wav("long.wav", frames: 44100 * 120)
        var polls = 0
        let info = SampleInfoLoader.load(path: path, canPreview: true, size: 44100 * 240, buckets: 300,
                                         isCancelled: { polls += 1; return polls > 2 })
        XCTAssertEqual(polls, 3)
        XCTAssertEqual(info.wave, .unavailable)
        XCTAssertEqual(info.durationMs, 120_000, "the header is still read")
    }

    func testSampleInfoPeaksAreTheLoudestFrameOfEachColumn() throws {
        var samples = [Int16](repeating: 0, count: 8000)
        samples[1500] = 16_384                                    // column 1 of 8
        samples[7999] = -32_768                                   // column 7
        let path = try wav("peaks.wav", samples: samples)
        let info = SampleInfoLoader.load(path: path, canPreview: true, size: 16_044, buckets: 8)
        guard case .peaks(let p) = info.wave else { return XCTFail("peaks expected") }
        XCTAssertEqual(p.count, 8)
        XCTAssertEqual(p[1], 0.5, accuracy: 1e-4)
        XCTAssertEqual(p[7], 1, accuracy: 1e-4)
        XCTAssertEqual(p[0], 0)
    }

    func testCancellingTheTaskReachesTheDecoder() async throws {
        let long = try wav("long.wav", frames: 44100 * 120)
        let counter = LockedCounter()
        let slow = Task { () -> Waveform in
            await BlockingWork.run { cancelled in
                WaveformReader.read(path: long, buckets: 300, isCancelled: { counter.bump(); return cancelled() })
            }
        }
        slow.cancel()                                             // before, or soon after, it starts
        let wave = await slow.value
        XCTAssertFalse(wave.ok, "the cancelled decode gave up instead of reading to the end")
        XCTAssertLessThan(counter.value, 20, "far fewer chunks than the 80 the file has")
    }
}
