// Port of src/AiffReader.cs (header only) plus the RIFF `fmt ` reader of src/WaveReader.cs.
// Upstream decodes AIFF by hand because Media Foundation has no AIFF source; on macOS
// AVFoundation plays AIFF, so only the header is needed: the walk marks the AIFFs it cannot play
// (Ableton's compressed AIFC "able", most of Live's packs — and a 512-byte header read is far
// cheaper than opening thirty thousand of them with AVAudioFile), and the panel shows the format.
import Foundation

/// What the header of an audio file says.
public struct AudioHeader: Equatable, Sendable {
    public var channels = 0
    public var rate = 0
    public var bits = 0
    public var frames: Int64 = 0
    /// AIFC compression tag ("NONE", "sowt", "able"…); "NONE" for plain AIFF and WAV.
    public var compression = "NONE"

    public init() {}

    public var durationMs: Int { rate > 0 ? Int(frames * 1000 / Int64(rate)) : 0 }
}

enum HeaderIO {
    /// Reads `count` bytes at `offset`; nil past the end.
    static func read(_ h: FileHandle, at offset: UInt64, _ count: Int) -> [UInt8]? {
        do {
            try h.seek(toOffset: offset)
            guard let d = try h.read(upToCount: count), d.count == count else { return nil }
            return [UInt8](d)
        } catch { return nil }
    }

    static func be16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
    static func be32(_ b: [UInt8], _ i: Int) -> Int64 {
        Int64(b[i]) << 24 | Int64(b[i + 1]) << 16 | Int64(b[i + 2]) << 8 | Int64(b[i + 3])
    }
    static func le16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    static func le32(_ b: [UInt8], _ i: Int) -> Int64 {
        Int64(b[i]) | Int64(b[i + 1]) << 8 | Int64(b[i + 2]) << 16 | Int64(b[i + 3]) << 24
    }
    static func tag(_ b: [UInt8], _ i: Int) -> String {
        String(decoding: b[i..<i + 4], as: UTF8.self)
    }
}

/// AIFF and AIFF-C headers.
public enum AiffReader {
    public static func isAiffName(_ path: String) -> Bool {
        ["aif", "aiff", "aifc"].contains((path as NSString).pathExtension.lowercased())
    }

    /// The 80-bit IEEE extended number of the COMM chunk (the sample rate).
    static func extended(_ b: [UInt8]) -> Double {
        let negative = b[0] & 0x80 != 0
        let exponent = (Int(b[0] & 0x7F) << 8) | Int(b[1])
        let hi = Double(HeaderIO.be32(b, 2)), lo = Double(HeaderIO.be32(b, 6))
        if exponent == 0 && hi == 0 && lo == 0 { return 0 }
        let v = (hi * 4_294_967_296 + lo) * pow(2, Double(exponent - 16383 - 63))
        return negative ? -v : v
    }

    /// nil — not an AIFF, or broken. Every pass over the chunks consumes at least the eight
    /// bytes of a chunk header, so a broken size cannot hold the loop in place.
    public static func readHeader(path: String) -> AudioHeader? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        guard let length = try? h.seekToEnd(), length >= 12,
              let top = HeaderIO.read(h, at: 0, 12), HeaderIO.tag(top, 0) == "FORM" else { return nil }
        let form = HeaderIO.tag(top, 8)
        let isAifc = form == "AIFC"
        guard form == "AIFF" || isAifc else { return nil }

        var header = AudioHeader()
        var gotComm = false, gotData = false
        var pos: UInt64 = 12
        while pos + 8 <= length {
            guard let ch = HeaderIO.read(h, at: pos, 8) else { break }
            let id = HeaderIO.tag(ch, 0)
            let size = UInt64(HeaderIO.be32(ch, 4))
            let body = pos + 8
            if id == "COMM" {
                let n = Int(min(size, 22))
                if n >= 18, let comm = HeaderIO.read(h, at: body, n) {
                    header.channels = HeaderIO.be16(comm, 0)
                    header.frames = HeaderIO.be32(comm, 2)
                    header.bits = HeaderIO.be16(comm, 6)
                    let rate = extended(Array(comm[8..<18]))
                    // A crafted exponent gives inf/NaN, which would trap in Int(_:).
                    header.rate = rate.isFinite && rate > 0 && rate < 1e7 ? Int(rate.rounded()) : 0
                    if isAifc, n >= 22 { header.compression = HeaderIO.tag(comm, 18) }
                    gotComm = true
                }
            } else if id == "SSND" {
                gotData = true
            }
            pos = body + size + (size & 1)
        }
        guard gotComm, gotData, header.channels > 0, header.rate > 0 else { return nil }
        return header
    }

    /// Whether the preview can play this AIFF: plain PCM ("NONE"/"twos" big-endian, "sowt"
    /// little-endian, "fl32" float). Ableton's "able" and every other codec: no.
    public static func canRead(path: String) -> Bool {
        guard let h = readHeader(path: path) else { return false }
        switch h.compression {
        case "NONE", "twos", "sowt": return [8, 16, 24, 32].contains(h.bits)
        case "fl32", "FL32": return true
        default: return false
        }
    }
}

/// RIFF/WAVE `fmt ` and `data` chunks.
public enum RiffReader {
    public static func readHeader(path: String) -> AudioHeader? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        guard let length = try? h.seekToEnd(), length >= 12,
              let top = HeaderIO.read(h, at: 0, 12),
              HeaderIO.tag(top, 0) == "RIFF" || HeaderIO.tag(top, 0) == "RF64",
              HeaderIO.tag(top, 8) == "WAVE" else { return nil }

        var header = AudioHeader()
        var blockAlign = 0
        var dataBytes: Int64 = -1
        var pos: UInt64 = 12
        while pos + 8 <= length {
            guard let ch = HeaderIO.read(h, at: pos, 8) else { break }
            let id = HeaderIO.tag(ch, 0)
            var size = UInt64(HeaderIO.le32(ch, 4))
            let body = pos + 8
            if id == "fmt ", size >= 16, let f = HeaderIO.read(h, at: body, 16) {
                header.channels = HeaderIO.le16(f, 2)
                header.rate = Int(HeaderIO.le32(f, 4))
                blockAlign = HeaderIO.le16(f, 12)
                header.bits = HeaderIO.le16(f, 14)
            } else if id == "data" {
                // A streamed or cut-short file claims more than it holds — the bytes are what counts.
                if size == 0xFFFF_FFFF || body + size > length { size = length - body }
                dataBytes = Int64(size)
                break
            }
            pos = body + size + (size & 1)
        }
        guard header.channels > 0, header.rate > 0, blockAlign > 0, dataBytes >= 0 else { return nil }
        header.frames = dataBytes / Int64(blockAlign)
        return header
    }
}

/// The header of any file whose format the core can read (WAV, AIFF); nil otherwise — the UI
/// asks AVFoundation for the rest.
public enum AudioFileInfo {
    public static func header(path: String) -> AudioHeader? {
        switch (path as NSString).pathExtension.lowercased() {
        case "wav", "wave": return RiffReader.readHeader(path: path)
        case "aif", "aiff", "aifc": return AiffReader.readHeader(path: path)
        default: return nil
        }
    }
}
