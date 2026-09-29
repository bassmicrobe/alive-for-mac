// Mac-only: a depth-aware push reader over the raw UTF-8 bytes (upstream used XmlReader).
// Hand-written tokenizer instead of Foundation's XMLParser, which ran at ~40 MB/s and was 95 %
// of a first library scan. Only element names (interned) and attribute values (lazily, on
// access) ever become `String`s; text content, comments and the `<Buffer>` hex blobs are skipped
// with memchr.
import Foundation

/// The attributes of one start tag. Values are decoded from the input bytes on access, so a tag
/// costs nothing for attributes nobody reads. Only valid inside the `onStart` callback that
/// received the tag: it points into the document buffer and a scratch table that is reused.
struct XMLAttrs {
    fileprivate let base: UnsafePointer<UInt8>
    fileprivate unowned(unsafe) let scratch: AttrScratch

    /// The attribute value (entities decoded, whitespace normalised), or nil when absent.
    subscript(key: String) -> String? {
        var key = key
        return key.withUTF8 { kb -> String? in
            for r in scratch.recs where r.nameLen == kb.count {
                if kb.count == 0 || memcmp(base + r.nameStart, kb.baseAddress!, kb.count) == 0 {
                    return value(of: r)
                }
            }
            return nil
        }
    }

    fileprivate init(base: UnsafePointer<UInt8>, scratch: AttrScratch) {
        self.base = base
        self.scratch = scratch
    }

    var count: Int { scratch.recs.count }

    /// Test support: lets a reference engine hand the real parsers dictionary attributes. One
    /// backing per engine; the attributes it returns are valid until the next `attrs(_:)` call
    /// (the same contract as production). Never used by `ElementStream`.
    final class TestBacking {
        private var bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        private var capacity = 4096
        private let scratch = AttrScratch()
        deinit { bytes.deallocate() }

        func attrs(_ dict: [String: String]) -> XMLAttrs {
            var used = 0
            scratch.recs.removeAll(keepingCapacity: true)
            func put(_ s: String) -> (Int, Int) {
                let u = Array(s.utf8)
                if used + u.count > capacity {   // grow; earlier records are re-pointed by offset, so this is safe
                    let nc = max(capacity * 2, used + u.count)
                    let nb = UnsafeMutablePointer<UInt8>.allocate(capacity: nc)
                    nb.update(from: bytes, count: used)
                    bytes.deallocate()
                    bytes = nb
                    capacity = nc
                }
                (bytes + used).update(from: u, count: u.count)
                used += u.count
                return (used - u.count, u.count)
            }
            for (k, v) in dict {
                let (ns, nl) = put(k), (vs, vl) = put(v)
                scratch.recs.append(AttrRec(nameStart: ns, nameLen: nl, valStart: vs, valLen: vl, decoded: nil))
            }
            return XMLAttrs(base: UnsafePointer(bytes), scratch: scratch)
        }
    }

    /// Everything as a dictionary (tests and diagnostics; the parsers use subscripts).
    var dictionary: [String: String] {
        var d: [String: String] = [:]
        for r in scratch.recs {
            let name = String(decoding: UnsafeBufferPointer(start: base + r.nameStart, count: r.nameLen), as: UTF8.self)
            d[name] = value(of: r)
        }
        return d
    }

    private func value(of r: AttrRec) -> String {
        r.decoded ?? String(decoding: UnsafeBufferPointer(start: base + r.valStart, count: r.valLen), as: UTF8.self)
    }
}

fileprivate struct AttrRec {
    var nameStart: Int, nameLen: Int, valStart: Int, valLen: Int
    /// Set only when the raw bytes needed entity decoding / whitespace normalisation.
    var decoded: String?
}

fileprivate final class AttrScratch {
    var recs: [AttrRec] = []
}

/// One XML start tag with the context the .als parsers need.
struct XMLTag {
    let name: String
    let attrs: XMLAttrs
    /// Name of the enclosing element ("" at the root).
    let parent: String
    /// Number of open ancestors, i.e. upstream's `stack.Count` before the push.
    let depth: Int

    /// The `Value` attribute, where nearly all Live data sits.
    var value: String? { attrs["Value"] }
    func int(_ fallback: Int = 0) -> Int { Int(attrs["Value"] ?? "") ?? fallback }
    func int64(_ fallback: Int64 = 0) -> Int64 { Int64(attrs["Value"] ?? "") ?? fallback }
    func double(_ fallback: Double = 0) -> Double { Double(attrs["Value"] ?? "") ?? fallback }
    var bool: Bool { (attrs["Value"] ?? "").lowercased() == "true" }
}

/// Interns element names: the same few hundred names repeat millions of times, so each distinct
/// name is decoded to a `String` once and later occurrences are found by hash over the bytes.
fileprivate struct NameTable {
    private struct Entry { var hash: UInt32; var off: Int; var len: Int; var string: String }
    private var entries: [Entry] = []
    private var blob: [UInt8] = []
    private var slots = [Int32](repeating: -1, count: 1024)

    func string(_ id: Int) -> String { entries[id].string }

    /// Id of the name at `p[0..<len]`, adding it on first sight.
    mutating func intern(_ p: UnsafePointer<UInt8>, _ len: Int) -> Int {
        var h: UInt32 = 2166136261
        for i in 0..<len { h = (h ^ UInt32(p[i])) &* 16777619 }
        var mask = slots.count - 1
        var s = Int(h) & mask
        while true {
            let e = Int(slots[s])
            if e < 0 { break }
            let en = entries[e]
            if en.hash == h, en.len == len,
               blob.withUnsafeBufferPointer({ memcmp($0.baseAddress! + en.off, p, len) == 0 }) {
                return e
            }
            s = (s + 1) & mask
        }
        let id = entries.count
        entries.append(Entry(hash: h, off: blob.count, len: len,
                             string: String(decoding: UnsafeBufferPointer(start: p, count: len), as: UTF8.self)))
        blob.append(contentsOf: UnsafeBufferPointer(start: p, count: len))
        slots[s] = Int32(id)
        if entries.count * 2 > slots.count {   // grow and re-place
            slots = [Int32](repeating: -1, count: slots.count * 2)
            mask = slots.count - 1
            for (i, en) in entries.enumerated() {
                var t = Int(en.hash) & mask
                while slots[t] >= 0 { t = (t + 1) & mask }
                slots[t] = Int32(i)
            }
        }
        return id
    }
}

/// Streams an XML document as start/end events. `end` receives the open-element count after the
/// pop — the same number upstream's `stack.Count` has at an EndElement — so the "close the
/// context when we leave its depth" checks port one to one. An empty element fires start and end
/// back to back, which is equivalent to upstream's `IsEmptyElement` special cases.
final class ElementStream {
    private let onStart: (XMLTag) -> Void
    private let onEnd: (Int) -> Void

    init(onStart: @escaping (XMLTag) -> Void, onEnd: @escaping (Int) -> Void) {
        self.onStart = onStart
        self.onEnd = onEnd
    }

    /// Parses; returns an error message when the document is broken or truncated
    /// (whatever was seen before the error has already been delivered).
    func run(_ data: Data) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return "XML parse error: empty document"
            }
            // Events before an invalid byte are still delivered (the input is cut there), like a
            // streaming parser that meets the bad byte mid-document.
            let bad = Self.firstInvalidUTF8(base, raw.count)
            let err = parse(base, bad)
            if bad < raw.count { return fail("invalid UTF-8 sequence", at: bad) }
            return err
        }
    }

    // MARK: byte classes

    @inline(__always) private static func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0D }
    /// ASCII letters, digits and `_ : . -`; every non-ASCII byte is accepted (UTF-8 letters).
    @inline(__always) private static func isNameChar(_ c: UInt8) -> Bool {
        (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39)
            || c == 0x5F || c == 0x3A || c == 0x2E || c == 0x2D || c >= 0x80
    }

    /// Scans an XML name at `i`: non-empty, not starting with a digit, `.` or `-`, and followed by
    /// whitespace, `>`, `/`, `=` (or `?` for a PI target) or the end of the input. Leaves `i` after it.
    @inline(__always)
    private static func scanName(_ p: UnsafePointer<UInt8>, _ n: Int, _ i: inout Int, pi: Bool = false) -> Bool {
        let s = i
        while i < n, isNameChar(p[i]) { i += 1 }
        if i == s { return false }
        let f = p[s]
        if (f >= 0x30 && f <= 0x39) || f == 0x2D || f == 0x2E { return false }
        guard i < n else { return true }
        let c = p[i]
        if pi { return isSpace(c) || c == 0x3F }
        return isSpace(c) || c == 0x3E || c == 0x2F || c == 0x3D
    }

    /// Index of the first byte that breaks UTF-8 well-formedness, or `n` when the whole input is
    /// valid. ASCII runs are skipped eight bytes at a time.
    private static func firstInvalidUTF8(_ p: UnsafePointer<UInt8>, _ n: Int) -> Int {
        var i = 0
        while i < n {
            while i + 8 <= n {
                let w = UnsafeRawPointer(p + i).loadUnaligned(as: UInt64.self)
                if w & 0x8080_8080_8080_8080 != 0 { break }
                i += 8
            }
            guard i < n else { break }
            let c = p[i]
            if c < 0x80 { i += 1; continue }
            let len: Int
            var lo: UInt8 = 0x80, hi: UInt8 = 0xBF   // allowed range of the second byte
            switch c {
            case 0xC2...0xDF: len = 2
            case 0xE0: len = 3; lo = 0xA0
            case 0xE1...0xEC, 0xEE...0xEF: len = 3
            case 0xED: len = 3; hi = 0x9F
            case 0xF0: len = 4; lo = 0x90
            case 0xF1...0xF3: len = 4
            case 0xF4: len = 4; hi = 0x8F
            default: return i
            }
            guard i + len <= n, p[i + 1] >= lo, p[i + 1] <= hi else { return i }
            for k in 2..<len where p[i + k] & 0xC0 != 0x80 { return i }
            i += len
        }
        return n
    }

    /// Checks the character data in `p[from..<to]` the way a validating reader would for the two
    /// cheap cases: `]]>` is not allowed in text and every `&` must start a known reference.
    private static func textIsValid(_ p: UnsafePointer<UInt8>, from: Int, to: Int) -> Bool {
        var k = from
        while k < to, let hit = memchr(p + k, 0x26, to - k) {
            let at = p.distance(to: hit.assumingMemoryBound(to: UInt8.self))
            guard let semi = memchr(p + at, 0x3B, to - at) else { return false }
            let e = p.distance(to: semi.assumingMemoryBound(to: UInt8.self))
            guard entityScalar(UnsafeBufferPointer(start: p + at + 1, count: e - at - 1)) != nil else { return false }
            k = e + 1
        }
        k = from
        while k < to, let hit = memchr(p + k, 0x3E, to - k) {   // '>' is rare in text
            let at = p.distance(to: hit.assumingMemoryBound(to: UInt8.self))
            if at >= from + 2, p[at - 1] == 0x5D, p[at - 2] == 0x5D { return false }
            k = at + 1
        }
        return true
    }

    private func fail(_ what: String, at i: Int) -> String { "XML parse error at byte \(i): \(what)" }

    // MARK: tokenizer

    private func parse(_ p: UnsafePointer<UInt8>, _ n: Int) -> String? {
        var i = 0
        if n >= 3, p[0] == 0xEF, p[1] == 0xBB, p[2] == 0xBF { i = 3 }
        var names = NameTable()
        var stack = ContiguousArray<Int>()
        stack.reserveCapacity(64)
        let scratch = AttrScratch()
        scratch.recs.reserveCapacity(16)
        var sawRoot = false

        while i < n {
            if p[i] != 0x3C {   // text
                if stack.isEmpty {
                    while i < n, Self.isSpace(p[i]) { i += 1 }
                    if i < n, p[i] != 0x3C { return fail("text outside the root element", at: i) }
                    continue
                }
                guard let hit = memchr(p + i, 0x3C, n - i) else { i = n; break }
                let next = p.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                if !Self.textIsValid(p, from: i, to: next) { return fail("invalid character data", at: i) }
                i = next
                continue
            }
            guard i + 1 < n else { return fail("unexpected end of document", at: i) }
            switch p[i + 1] {
            case 0x2F:   // </name>
                i += 2
                let s = i
                if !Self.scanName(p, n, &i) { return fail("invalid end tag name", at: s) }
                let id = names.intern(p + s, i - s)
                while i < n, Self.isSpace(p[i]) { i += 1 }
                guard i < n else { return fail("unterminated end tag", at: n) }
                guard p[i] == 0x3E else { return fail("malformed end tag", at: i) }
                i += 1
                guard let top = stack.last, top == id else { return fail("mismatched end tag", at: s) }
                stack.removeLast()
                onEnd(stack.count)
            case 0x3F:   // <? ... ?>
                var t = i + 2
                if !Self.scanName(p, n, &t, pi: true) { return fail("invalid processing instruction target", at: i) }
                guard let e = Self.find(p, n, from: i + 2, "?>") else {
                    return fail("unterminated processing instruction", at: i)
                }
                i = e + 2
            case 0x21:   // <! comment / CDATA / DOCTYPE
                guard let e = Self.skipBang(p, n, i, inRoot: !stack.isEmpty) else {
                    return fail("malformed or unterminated <! construct", at: i)
                }
                i = e
            default:
                if stack.isEmpty, sawRoot { return fail("extra content after the root element", at: i) }
                sawRoot = true
                i += 1
                let s = i
                if !Self.scanName(p, n, &i) { return fail("invalid element name", at: s) }
                let id = names.intern(p + s, i - s)
                scratch.recs.removeAll(keepingCapacity: true)
                var selfClose = false
                var first = true   // the name itself counts as a separator before the first attribute
                attrs: while true {
                    let before = i
                    while i < n, Self.isSpace(p[i]) { i += 1 }
                    guard i < n else { return fail("unterminated start tag", at: n) }
                    switch p[i] {
                    case 0x3E:
                        i += 1
                        break attrs
                    case 0x2F:
                        guard i + 1 < n else { return fail("unterminated start tag", at: n) }
                        guard p[i + 1] == 0x3E else { return fail("stray '/' in start tag", at: i) }
                        i += 2
                        selfClose = true
                        break attrs
                    default:
                        if !first, i == before { return fail("missing whitespace between attributes", at: i) }
                        if let err = Self.readAttribute(p, n, &i, scratch) { return fail(err, at: i) }
                        first = false
                    }
                }
                let tag = XMLTag(name: names.string(id), attrs: XMLAttrs(base: p, scratch: scratch),
                                 parent: stack.last.map { names.string($0) } ?? "", depth: stack.count)
                onStart(tag)
                if selfClose { onEnd(stack.count) } else { stack.append(id) }
            }
        }
        if !sawRoot { return fail("document has no root element", at: n) }
        if !stack.isEmpty { return fail("unexpected end of document, \(stack.count) element(s) still open", at: n) }
        return nil
    }

    private static func has(_ p: UnsafePointer<UInt8>, _ n: Int, _ i: Int, _ s: StaticString) -> Bool {
        i + s.utf8CodeUnitCount <= n && memcmp(p + i, s.utf8Start, s.utf8CodeUnitCount) == 0
    }

    /// First index >= `from` where the ASCII `pat` starts.
    private static func find(_ p: UnsafePointer<UInt8>, _ n: Int, from: Int, _ pat: StaticString) -> Int? {
        let pb = pat.utf8Start, plen = pat.utf8CodeUnitCount
        var i = from
        while i + plen <= n {
            guard let hit = memchr(p + i, Int32(pb[0]), n - i - plen + 1) else { return nil }
            let at = p.distance(to: hit.assumingMemoryBound(to: UInt8.self))
            if memcmp(p + at, pb, plen) == 0 { return at }
            i = at + 1
        }
        return nil
    }

    /// Skips a comment, CDATA section or DOCTYPE starting at `<!` (index `i`); returns the index
    /// after it, or nil when malformed/unterminated.
    private static func skipBang(_ p: UnsafePointer<UInt8>, _ n: Int, _ i: Int, inRoot: Bool) -> Int? {
        if has(p, n, i, "<!--") {
            guard let e = find(p, n, from: i + 4, "-->") else { return nil }
            var k = i + 4   // "--" may only appear as the start of the terminator
            while k < e, let hit = memchr(p + k, 0x2D, e - k) {
                let at = p.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                if at + 1 < e + 1, p[at + 1] == 0x2D, at < e { return nil }
                k = at + 1
            }
            return e + 3
        }
        if has(p, n, i, "<![CDATA[") {
            guard inRoot else { return nil }
            return find(p, n, from: i + 9, "]]>").map { $0 + 3 }
        }
        guard has(p, n, i, "<!DOCTYPE") else { return nil }
        guard !inRoot, i + 9 < n, isSpace(p[i + 9]) else { return nil }
        var j = i + 9, bracket = 0
        while j < n, isSpace(p[j]) { j += 1 }
        guard scanName(p, n, &j), j < n, isSpace(p[j]) || p[j] == 0x3E || p[j] == 0x5B else { return nil }
        while j < n {
            let c = p[j]
            if c == 0x22 || c == 0x27 {
                guard let q = memchr(p + j + 1, Int32(c), n - j - 1) else { return nil }
                j = p.distance(to: q.assumingMemoryBound(to: UInt8.self)) + 1
                continue
            }
            if c == 0x5B { bracket += 1 } else if c == 0x5D { bracket -= 1 }
            else if c == 0x3E, bracket <= 0 { return j + 1 }
            else if c == 0x3C, has(p, n, j, "<!--") {   // a subset comment may hold '>' or quotes
                guard let e = find(p, n, from: j + 4, "-->") else { return nil }
                j = e + 3
                continue
            }
            j += 1
        }
        return nil
    }

    static let maxAttributesPerTag = 1024

    /// Reads `name = "value"` at `i`; appends a record; returns an error text or nil.
    private static func readAttribute(_ p: UnsafePointer<UInt8>, _ n: Int, _ i: inout Int,
                                      _ scratch: AttrScratch) -> String? {
        let ns = i
        if !scanName(p, n, &i) { return "invalid attribute name" }
        let nl = i - ns
        while i < n, isSpace(p[i]) { i += 1 }
        guard i < n, p[i] == 0x3D else { return i < n ? "attribute without value" : "unterminated start tag" }
        i += 1
        while i < n, isSpace(p[i]) { i += 1 }
        guard i < n else { return "unterminated start tag" }
        let quote = p[i]
        guard quote == 0x22 || quote == 0x27 else { return "attribute value not quoted" }
        i += 1
        let vs = i
        var needsDecode = false
        while i < n {
            let c = p[i]
            if c == quote { break }
            if c == 0x3C { return "'<' in attribute value" }
            if c == 0x26 || c == 0x0A || c == 0x09 || c == 0x0D { needsDecode = true }
            i += 1
        }
        guard i < n else { return "unterminated attribute value" }
        let vl = i - vs
        i += 1
        // The duplicate check below is linear in the attributes so far: cap them, or a tag with
        // a million attributes costs a trillion comparisons.
        if scratch.recs.count >= Self.maxAttributesPerTag { return "too many attributes in one tag" }
        for r in scratch.recs where r.nameLen == nl && memcmp(p + r.nameStart, p + ns, nl) == 0 {
            return "duplicate attribute"
        }
        var decoded: String?
        if needsDecode {
            guard let s = decode(p + vs, vl) else { return "invalid entity reference in attribute value" }
            decoded = s
        }
        scratch.recs.append(AttrRec(nameStart: ns, nameLen: nl, valStart: vs, valLen: vl, decoded: decoded))
        return nil
    }

    /// Entity decoding + attribute-value normalisation (tab/CR/LF become a space, CRLF one space).
    /// nil on an unknown or malformed entity.
    private static func decode(_ p: UnsafePointer<UInt8>, _ len: Int) -> String? {
        var out = [UInt8]()
        out.reserveCapacity(len)
        var i = 0
        while i < len {
            let c = p[i]
            switch c {
            case 0x09, 0x0A:
                out.append(0x20)
                i += 1
            case 0x0D:
                out.append(0x20)
                i += (i + 1 < len && p[i + 1] == 0x0A) ? 2 : 1
            case 0x26:
                guard let semi = memchr(p + i, 0x3B, len - i) else { return nil }
                let e = p.distance(to: semi.assumingMemoryBound(to: UInt8.self))
                guard let scalar = entityScalar(UnsafeBufferPointer(start: p + i + 1, count: e - i - 1)) else { return nil }
                out.append(contentsOf: Array(String(Character(scalar)).utf8))
                i = e + 1
            default:
                out.append(c)
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func entityScalar(_ b: UnsafeBufferPointer<UInt8>) -> Unicode.Scalar? {
        guard let f = b.first else { return nil }
        if f == 0x23 {   // &#NN; / &#xHH;
            let hex = b.count > 1 && b[1] == 0x78
            var k = hex ? 2 : 1
            guard k < b.count else { return nil }
            var v: UInt32 = 0
            while k < b.count {
                let d = b[k]
                let digit: UInt32
                switch d {
                case 0x30...0x39: digit = UInt32(d - 0x30)
                case 0x61...0x66 where hex: digit = UInt32(d - 0x61 + 10)
                case 0x41...0x46 where hex: digit = UInt32(d - 0x41 + 10)
                default: return nil
                }
                v = v * (hex ? 16 : 10) + digit
                if v > 0x10FFFF { return nil }
                k += 1
            }
            if v < 0x20 && v != 9 && v != 10 && v != 13 { return nil }   // not an XML Char
            return Unicode.Scalar(v)
        }
        switch String(decoding: b, as: UTF8.self) {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default: return nil
        }
    }
}
