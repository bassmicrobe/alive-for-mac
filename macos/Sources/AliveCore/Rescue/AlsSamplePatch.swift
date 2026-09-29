// Port of src/AlsSamplePatch.cs
import Foundation

/// Where one file reference should start pointing.
public struct NewRef: Equatable, Sendable {
    /// "Samples/Imported/kick.wav" — forward slashes, the way Live writes them.
    public var relativePath = ""
    /// The full path in the new place, forward slashes too.
    public var absolutePath = ""
    /// 3 — "inside the project folder", see `RefResolver`.
    public var relativePathType = 3
    /// Clear LivePackName and LivePackId: the file no longer comes from a pack.
    public var clearPack = true

    public init(relativePath: String = "", absolutePath: String = "", relativePathType: Int = 3,
                clearPack: Bool = true) {
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.relativePathType = relativePathType
        self.clearPack = clearPack
    }
}

public enum AlsSamplePatchError: Error, Equatable {
    /// The number of FileRefs found by the patcher differs from the parser's: the numbering has
    /// drifted and the edit would land on the wrong reference.
    case refCountMismatch(found: Int, expected: Int)
}

/// A copy of a set with the paths of selected references replaced.
///
/// Nodes are addressed by their NUMBER in document order, not by their content. In the text one
/// `<FileRef>` is indistinguishable from its neighbour: the path of a clip's sample and of its
/// "memory of origin" can be literally the same, and only the first must be rewritten. `AlsFile`
/// already walks the file and fills `info.files` in order, so the i-th entry in that list is the
/// i-th `<FileRef>` in the text. That keeps the "which container is this" logic in one place.
///
/// The mechanics are the same as `AlsPatch`: streaming, line by line, with only the current node
/// in memory. The original is never opened for writing.
public enum AlsSamplePatch {
    private static let open = Array("<FileRef".utf8)
    private static let close = Array("</FileRef>".utf8)

    /// Writes a copy of `src` into `dst` with the paths replaced. Returns the number of nodes
    /// touched.
    ///
    /// `expectedRefCount` is how many FileRefs `AlsFile` counted in this same file. A mismatch
    /// deletes `dst` and throws: writing a wrong path into a sample reference is worse than
    /// writing nothing — the set will open, but it will sound like something else.
    @discardableResult
    public static func rewrite(src: String, dst: String, byIndex: [Int: NewRef],
                               expectedRefCount: Int,
                               isCancelled: () -> Bool = { false }) throws -> Int {
        var index = -1, patched = 0
        var ok = false

        let reader = try GzipLineReader(path: src)
        // Created exclusively: if `dst` already exists this throws and nothing is removed —
        // only a file this call created is ever deleted on failure.
        let writer = try GzipLineWriter(path: dst)
        defer { if !ok { try? FileManager.default.removeItem(atPath: dst) } }
        var node: [UInt8]?

        while let line = try reader.next() {
            if isCancelled() { throw CancellationError() }
            if node == nil {
                // A self-closing <FileRef /> is skipped by both parsers: AlsFile only makes an
                // entry when the element has children.
                guard opensFileRef(line) else { try writer.write(line); continue }
                index += 1
                node = line
            } else {
                node?.append(contentsOf: line)
            }
            // Looked for in the current line, not in everything accumulated.
            guard ByteSearch.contains(close, in: line) else { continue }

            let bytes = node ?? []
            node = nil
            if let nr = byIndex[index] {
                try writer.write(apply(String(decoding: bytes, as: UTF8.self), nr))
                patched += 1
            } else {
                try writer.write(bytes)
            }
        }
        if let node { try writer.write(node) }       // ended mid-node: keep the tail
        try writer.finish()

        guard index + 1 == expectedRefCount else {
            throw AlsSamplePatchError.refCountMismatch(found: index + 1, expected: expectedRefCount)
        }
        ok = true
        Diag.info("collect: rewrote \(patched) FileRef in \((dst as NSString).lastPathComponent)")
        return patched
    }

    /// `<FileRef …>` (not `<FileRefX`, not self-closing).
    private static func opensFileRef(_ line: [UInt8]) -> Bool {
        guard let at = ByteSearch.find(open, in: line) else { return false }
        let after = at + open.count
        guard after < line.count else { return true }
        let c = line[after]
        guard c == 0x3E || c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x2F else { return false }
        // Self-closing: a "/" right before the tag's closing bracket.
        guard let end = line[at...].firstIndex(of: 0x3E) else { return true }
        return line[end - 1] != 0x2F
    }

    static func apply(_ node: String, _ nr: NewRef) -> String {
        var s = node
        // The leading "<" is not decoration: without it "<RelativePath Value=" would be found by
        // a search for "Path Value=" and the path would go into the wrong tag.
        s = setValue(s, "<RelativePathType Value=\"", String(nr.relativePathType))
        s = setValue(s, "<RelativePath Value=\"", escape(nr.relativePath))
        s = setValue(s, "<Path Value=\"", escape(nr.absolutePath))
        if nr.clearPack {
            s = setValue(s, "<LivePackName Value=\"", "")
            s = setValue(s, "<LivePackId Value=\"", "")
        }
        // Type, OriginalFileSize and OriginalCrc are left alone: they are about the same file,
        // which has merely moved.
        return s
    }

    /// Replaces the value of the first such tag in the node. No tag — the node stays as it was.
    static func setValue(_ node: String, _ tag: String, _ value: String) -> String {
        guard let at = node.range(of: tag), let close = node[at.upperBound...].firstIndex(of: "\"") else {
            return node
        }
        return node[..<at.upperBound] + value + node[close...]
    }

    /// XML-escaping of an attribute value: a folder called "Drum & Bass" turns up all the time
    /// and, written as is, tears the document apart. Also normalises "\" into "/": paths in an
    /// .als are always forward-slashed.
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count + 8)
        for c in s {
            switch c {
            case "\\": out.append("/")
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }
}
