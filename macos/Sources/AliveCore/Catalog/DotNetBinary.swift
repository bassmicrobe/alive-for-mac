// Mac-only: reader/writer for .NET BinaryWriter/BinaryReader layout, so index.cache and
// activity.cache keep upstream's on-disk format.
import Foundation

enum BinaryFormatError: Error { case truncated, badString }

/// Little-endian primitives; strings are a 7-bit-encoded (LEB128) UTF-8 byte count + bytes.
struct DotNetWriter {
    private(set) var data = Data()

    mutating func int32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func int64(_ v: Int64) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func double(_ v: Double) { int64(Int64(bitPattern: v.bitPattern)) }
    mutating func bool(_ v: Bool) { data.append(v ? 1 : 0) }
    mutating func string(_ s: String) {
        let bytes = Array(s.utf8)
        var n = bytes.count
        repeat {
            var b = UInt8(n & 0x7F)
            n >>= 7
            if n > 0 { b |= 0x80 }
            data.append(b)
        } while n > 0
        data.append(contentsOf: bytes)
    }
}

struct DotNetReader {
    private let data: Data
    private var pos: Int

    init(_ data: Data) { self.data = data; self.pos = data.startIndex }

    var isAtEnd: Bool { pos >= data.endIndex }

    private mutating func take(_ n: Int) throws -> Data {
        guard n >= 0, pos + n <= data.endIndex else { throw BinaryFormatError.truncated }
        defer { pos += n }
        return data.subdata(in: pos..<pos + n)
    }

    mutating func int32() throws -> Int32 {
        try take(4).withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(as: Int32.self)) }
    }
    mutating func int64() throws -> Int64 {
        try take(8).withUnsafeBytes { Int64(littleEndian: $0.loadUnaligned(as: Int64.self)) }
    }
    mutating func double() throws -> Double { Double(bitPattern: UInt64(bitPattern: try int64())) }
    mutating func bool() throws -> Bool { try take(1)[0] != 0 }
    mutating func string() throws -> String {
        var length = 0, shift = 0
        while true {
            let b = try take(1)[0]
            length |= Int(b & 0x7F) << shift
            if b & 0x80 == 0 { break }
            shift += 7
            if shift > 28 { throw BinaryFormatError.badString }
        }
        guard let s = String(data: try take(length), encoding: .utf8) else { throw BinaryFormatError.badString }
        return s
    }
}

/// .NET `DateTime.Ticks`: 100 ns units since 0001-01-01.
enum DotNetTicks {
    static let unixEpoch: Int64 = 621_355_968_000_000_000

    /// A UTC instant as ticks.
    static func utc(_ d: Date) -> Int64 { unixEpoch + Int64((d.timeIntervalSince1970 * 1e7).rounded()) }
    static func date(utc ticks: Int64) -> Date { Date(timeIntervalSince1970: Double(ticks - unixEpoch) / 1e7) }

    /// Local wall-clock ticks (upstream stores DateTimeKind.Local values in activity.cache).
    static func local(_ d: Date) -> Int64 {
        utc(d) + Int64(TimeZone.current.secondsFromGMT(for: d)) * 10_000_000
    }
    static func date(local ticks: Int64) -> Date {
        let wall = date(utc: ticks)
        return wall.addingTimeInterval(-Double(TimeZone.current.secondsFromGMT(for: wall)))
    }

    /// Whether two instants are the same 100 ns tick (tolerating double rounding).
    static func sameInstant(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) < 1e-6 }
}
