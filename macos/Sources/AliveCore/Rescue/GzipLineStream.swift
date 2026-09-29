// Mac-only: streaming gzip line reader/writer over system zlib. Upstream streams through
// GZipStream + StreamReader (AlsPatch.LineReader); one set can unpack to 177 MB of XML, so the
// patchers never hold the document in memory — only the current line and node.
import CZlib
import Foundation

/// Reads a (gzip or plain) file line by line; each line keeps its ending, so a copy can be
/// written byte for byte. A file that does not start with the gzip magic is read as plain XML,
/// like `Gzip.readMaybeGzip`.
final class GzipLineReader {
    private let handle: FileHandle
    private var stream = z_stream()
    private var inflating = false
    private var finished = false
    private var raw: Bool
    private var pending: [UInt8] = []
    private var pos = 0
    private var scan = 0
    private let chunk = 256 * 1024
    private let maxLine: Int
    private let maxTotal: Int
    private var total = 0

    /// `maxLine` bounds a line without a newline (a file that is not a text set would otherwise
    /// grow `pending` without limit); `maxTotal` bounds the inflated bytes (a bomb).
    /// Both throw `GzipError.tooLarge`.
    init(path: String, maxLine: Int = 512 * 1024 * 1024, maxTotal: Int = Gzip.maxInflatedBytes) throws {
        self.maxLine = maxLine
        self.maxTotal = maxTotal
        guard let h = FileHandle(forReadingAtPath: path) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: path])
        }
        handle = h
        let head = try h.read(upToCount: 2) ?? Data()
        try h.seek(toOffset: 0)
        raw = !(head.count == 2 && head[head.startIndex] == 0x1F && head[head.startIndex + 1] == 0x8B)
        if !raw {
            let rc = inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard rc == Z_OK else { throw GzipError.initFailed(code: rc) }
            inflating = true
        }
    }

    deinit {
        if inflating { inflateEnd(&stream) }
        try? handle.close()
    }

    /// The next line with its `\n` (the last one may have none); nil at the end.
    func next() throws -> [UInt8]? {
        while true {
            if let nl = newline(from: scan) {
                let line = Array(pending[pos...nl])
                pos = nl + 1
                scan = pos
                return line
            }
            scan = pending.count
            if finished {
                guard pos < pending.count else { return nil }
                let rest = Array(pending[pos...])
                pending = []
                pos = 0
                scan = 0
                return rest
            }
            if pos > 0 {                       // compact once per chunk, not once per line
                pending.removeSubrange(0..<pos)
                scan -= pos
                pos = 0
            }
            try fill()
            if pending.count - pos > maxLine || total > maxTotal { throw GzipError.tooLarge }
        }
    }

    private func newline(from: Int) -> Int? {
        guard from < pending.count else { return nil }
        return pending.withUnsafeBufferPointer { buf -> Int? in
            guard let hit = memchr(buf.baseAddress! + from, 0x0A, buf.count - from) else { return nil }
            return buf.baseAddress!.distance(to: hit.assumingMemoryBound(to: UInt8.self))
        }
    }

    /// Reads and (if needed) inflates one more chunk into `pending`.
    private func fill() throws {
        guard let data = try handle.read(upToCount: chunk), !data.isEmpty else {
            if inflating, !finished { throw GzipError.corrupt(code: Z_BUF_ERROR) }   // truncated
            finished = true
            return
        }
        if raw { pending.append(contentsOf: data); total += data.count; return }

        var input = [UInt8](data)
        var out = [UInt8](repeating: 0, count: chunk)
        var streamEnded = false
        let before = pending.count
        try input.withUnsafeMutableBufferPointer { inBuf in
            stream.next_in = inBuf.baseAddress
            stream.avail_in = uInt(inBuf.count)
            // Keep going while input is left OR the last call filled the output buffer
            // completely: zlib may still hold pending output with all input consumed.
            var again = true
            while again {
                let status = out.withUnsafeMutableBufferPointer { o -> Int32 in
                    stream.next_out = o.baseAddress
                    stream.avail_out = uInt(o.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                // No progress possible without more input (the buffer was filled exactly).
                if status == Z_BUF_ERROR && stream.avail_in == 0 { break }
                guard status == Z_OK || status == Z_STREAM_END else { throw GzipError.corrupt(code: status) }
                let produced = out.count - Int(stream.avail_out)
                pending.append(contentsOf: out[0..<produced])
                if status == Z_STREAM_END { streamEnded = true }
                // A bomb is stopped as it grows, not after the chunk is fully inflated.
                if pending.count - pos > maxLine || total + pending.count - before > maxTotal { throw GzipError.tooLarge }
                again = !streamEnded && (stream.avail_in > 0 || stream.avail_out == 0)
            }
        }
        total += pending.count - before
        if streamEnded { finished = true }
    }
}

/// Writes lines/bytes through a gzip stream into a new file (never an existing one: the
/// patchers only create copies).
final class GzipLineWriter {
    private let handle: FileHandle
    private var stream = z_stream()
    private var open = true
    private var buffer: [UInt8] = []
    private let flushAt = 256 * 1024

    init(path: String) throws {
        // O_EXCL: never truncate or reuse what is already there — the file might be the
        // user's. A failed open is reported and nothing is removed by the caller.
        let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        guard fd >= 0 else {
            let code: CocoaError.Code = errno == EEXIST ? .fileWriteFileExists : .fileWriteUnknown
            throw CocoaError(code, userInfo: [NSFilePathErrorKey: path])
        }
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let rc = deflateInit2_(&stream, 6, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY,
                               ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard rc == Z_OK else { throw GzipError.initFailed(code: rc) }
    }

    deinit {
        if open { deflateEnd(&stream); try? handle.close() }
    }

    func write(_ bytes: [UInt8]) throws {
        buffer.append(contentsOf: bytes)
        if buffer.count >= flushAt { try drain(final: false) }
    }

    func write(_ text: String) throws { try write(Array(text.utf8)) }

    /// Flushes the deflate stream and closes the file.
    func finish() throws {
        guard open else { return }
        try drain(final: true)
        deflateEnd(&stream)
        open = false
        try handle.close()
    }

    private func drain(final: Bool) throws {
        var input = buffer
        buffer = []
        var out = [UInt8](repeating: 0, count: flushAt)
        try input.withUnsafeMutableBufferPointer { inBuf in
            stream.next_in = inBuf.baseAddress
            stream.avail_in = uInt(inBuf.count)
            var status: Int32 = Z_OK
            repeat {
                status = out.withUnsafeMutableBufferPointer { o -> Int32 in
                    stream.next_out = o.baseAddress
                    stream.avail_out = uInt(o.count)
                    return deflate(&stream, final ? Z_FINISH : Z_NO_FLUSH)
                }
                guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
                    throw GzipError.corrupt(code: status)
                }
                let produced = out.count - Int(stream.avail_out)
                if produced > 0 { try handle.write(contentsOf: Data(out[0..<produced])) }
            } while stream.avail_out == 0 || (final && status != Z_STREAM_END)
        }
    }
}

/// Byte-level substring search shared by the patchers.
enum ByteSearch {
    static func find(_ needle: [UInt8], in hay: [UInt8]) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count else { return nil }
        return hay.withUnsafeBufferPointer { h in
            needle.withUnsafeBufferPointer { n in
                memmem(h.baseAddress!, h.count, n.baseAddress!, n.count).map { h.baseAddress!.distance(to: $0.assumingMemoryBound(to: UInt8.self)) }
            }
        }
    }

    static func contains(_ needle: [UInt8], in hay: [UInt8]) -> Bool { find(needle, in: hay) != nil }
}
