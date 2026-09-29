// Mac-only: gzip via system zlib (upstream used System.IO.Compression.GZipStream).
import CZlib
import Foundation

public enum GzipError: Error, Equatable {
    case corrupt(code: Int32)
    case initFailed(code: Int32)
    /// The inflated output passed the cap: a decompression bomb, or a file that is not a set.
    case tooLarge
}

/// gzip container helpers for .als files (gzip over XML).
public enum Gzip {
    private static let chunk = 256 * 1024
    /// Real sets inflate to at most a few hundred MB; anything past this is not a set.
    public static let maxInflatedBytes = 2 * 1024 * 1024 * 1024

    public static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    /// Inflates gzip (or zlib) data; windowBits 15+32 auto-detects the header.
    public static func decompress(_ data: Data, limit: Int = Gzip.maxInflatedBytes) throws -> Data {
        var stream = z_stream()
        let rc = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard rc == Z_OK else { throw GzipError.initFailed(code: rc) }
        defer { inflateEnd(&stream) }

        var out = Data()
        var buffer = [UInt8](repeating: 0, count: chunk)
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer<Bytef>(
                mutating: raw.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(raw.count)
            var status: Int32 = Z_OK
            repeat {
                status = buffer.withUnsafeMutableBufferPointer { buf -> Int32 in
                    stream.next_out = buf.baseAddress
                    stream.avail_out = uInt(chunk)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                if status != Z_OK && status != Z_STREAM_END { throw GzipError.corrupt(code: status) }
                out.append(buffer, count: chunk - Int(stream.avail_out))
                if out.count > limit { throw GzipError.tooLarge }
                // Input exhausted without reaching the end marker: a truncated stream.
                if status == Z_OK && stream.avail_in == 0 && stream.avail_out != 0 {
                    throw GzipError.corrupt(code: Z_BUF_ERROR)
                }
            } while status != Z_STREAM_END
        }
        return out
    }

    /// Deflates to a gzip container (windowBits 31).
    public static func compress(_ data: Data, level: Int32 = 6) throws -> Data {
        var stream = z_stream()
        let rc = deflateInit2_(&stream, level, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY,
                               ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard rc == Z_OK else { throw GzipError.initFailed(code: rc) }
        defer { deflateEnd(&stream) }

        var out = Data()
        var buffer = [UInt8](repeating: 0, count: chunk)
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer<Bytef>(
                mutating: raw.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(raw.count)
            var status: Int32 = Z_OK
            repeat {
                status = buffer.withUnsafeMutableBufferPointer { buf -> Int32 in
                    stream.next_out = buf.baseAddress
                    stream.avail_out = uInt(chunk)
                    return deflate(&stream, Z_FINISH)
                }
                if status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR {
                    throw GzipError.corrupt(code: status)
                }
                out.append(buffer, count: chunk - Int(stream.avail_out))
            } while status != Z_STREAM_END
        }
        return out
    }

    /// Reads a file: gzip is inflated, anything else is returned as is (plain XML).
    /// Read into memory, never memory-mapped: Live may truncate a plain-XML set while it is
    /// parsed, and touching a truncated mapping is a SIGBUS.
    public static func readMaybeGzip(path: String, limit: Int = Gzip.maxInflatedBytes) throws -> Data {
        let raw = try Data(contentsOf: URL(fileURLWithPath: path))
        if isGzip(raw) { return try decompress(raw, limit: limit) }
        if raw.count > limit { throw GzipError.tooLarge }
        return raw
    }
}
