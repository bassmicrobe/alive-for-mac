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
    /// Decompression-bomb guard, not a memory budget (that is `AlsFile.inflateBudget`). The largest
    /// real set seen inflates to ~92 MB, big orchestral templates reach a few hundred MB; anything
    /// past this is not a set, and is recorded as unreadable.
    public static let maxInflatedBytes = 512 * 1024 * 1024

    public static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    /// The inflated size a gzip file announces in its trailer (ISIZE, the size modulo 2^32), or
    /// nil for anything else. A hint only — a lying trailer is clamped to what deflate can
    /// possibly produce (about 1032:1) so it cannot request a huge allocation.
    public static func inflatedSizeHint(_ data: Data) -> Int? {
        guard isGzip(data), data.count >= 18 else { return nil }
        let e = data.endIndex
        let size = Int(data[e - 4]) | Int(data[e - 3]) << 8 | Int(data[e - 2]) << 16 | Int(data[e - 1]) << 24
        return min(size, data.count * 1032)
    }

    /// Inflates gzip (or zlib) data; windowBits 15+32 auto-detects the header. `initialCapacity`
    /// overrides the size the output is first mapped at (tests use it to exercise growth).
    /// `lease`, when given, is kept covering every byte actually mapped (growth included, both
    /// mappings while one is copied into the other); on return it covers the result's mapping.
    ///
    /// The output lives in an anonymous mapping of its own, written by zlib directly (no chunk
    /// buffer, no growth by copying), and is unmapped the moment the returned `Data` dies. A
    /// `malloc` block of a few MB freed by a scan worker is kept by the allocator's cache instead
    /// of going back to the system: 750 sets in a row held 650 MB of such empty blocks.
    public static func decompress(_ data: Data, limit: Int = Gzip.maxInflatedBytes,
                                  initialCapacity: Int? = nil, lease: ByteBudget.Lease? = nil) throws -> Data {
        var stream = z_stream()
        let rc = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard rc == Z_OK else { throw GzipError.initFailed(code: rc) }
        defer { inflateEnd(&stream) }

        let page = Int(getpagesize())
        func rounded(_ n: Int) -> Int { (n + page - 1) / page * page }
        // The trailer's size when there is one (+1 so the end marker fits without growing).
        var capacity = rounded(max(min(initialCapacity ?? (inflatedSizeHint(data) ?? data.count * 8) + 1, limit + 1), 1))
        lease?.ensure(capacity)
        var base = try map(capacity)
        var length = 0
        var handedOver = false
        defer { if !handedOver { munmap(base, capacity) } }

        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer<Bytef>(
                mutating: raw.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(raw.count)
            var status: Int32 = Z_OK
            repeat {
                if length == capacity {          // full without the end marker: grow
                    let bigger = rounded(min(capacity * 2, limit + page))
                    lease?.ensure(capacity + bigger)      // both mappings exist while copying
                    let next = try map(bigger)
                    memcpy(next, base, length)
                    munmap(base, capacity)
                    base = next; capacity = bigger
                    lease?.shrink(to: capacity)
                }
                stream.next_out = base.advanced(by: length).assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(min(capacity - length, Int(UInt32.max)))
                status = inflate(&stream, Z_NO_FLUSH)
                if status != Z_OK && status != Z_STREAM_END { throw GzipError.corrupt(code: status) }
                length = capacity - Int(stream.avail_out)
                if length > limit { throw GzipError.tooLarge }
                // Input exhausted without reaching the end marker: a truncated stream.
                if status == Z_OK && stream.avail_in == 0 && stream.avail_out != 0 {
                    throw GzipError.corrupt(code: Z_BUF_ERROR)
                }
            } while status != Z_STREAM_END
        }
        handedOver = true
        let (mapped, size) = (base, capacity)
        return Data(bytesNoCopy: mapped, count: length, deallocator: .custom { _, _ in munmap(mapped, size) })
    }

    private static func map(_ size: Int) throws -> UnsafeMutableRawPointer {
        let p = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0)
        guard let p, p != MAP_FAILED else { throw GzipError.tooLarge }
        return p
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
