// Port of src/Arrangement.cs (model and parsing only; the drawing is ported separately).
import Foundation

/// One note. `time` is in beats from the start of the clip's content, not of the set.
public struct NoteEvent: Equatable, Sendable {
    public var time: Float = 0
    public var duration: Float = 0
    public var pitch: UInt8 = 0
    public var velocity: UInt8 = 0
}

/// A clip on the arrangement ruler.
public struct ClipBlock: Sendable {
    /// Beats from the start of the set.
    public var start = 0.0, end = 0.0
    public var name = ""
    public var color = -1
    public var isMidi = false, disabled = false

    /// The clip's visible markers. With the loop off, Live keeps the start/end marker bounds in
    /// LoopStart/LoopEnd and moves the hidden loop into HiddenLoop*.
    public var loopStart = 0.0, loopEnd = 0.0, startRelative = 0.0
    public var loopOn = false

    /// midi clips only
    public var notes: [NoteEvent]?
    public var minPitch = 127, maxPitch = 0

    public var length: Double { end - start }
    public var loopLength: Double { loopEnd - loopStart }
}

public struct TrackLane: Sendable {
    public var name = ""
    public var color = -1
    public var isMidi = false, isGroup = false, frozen = false
    public var id = -1, groupId = -1
    /// Nesting depth in groups.
    public var indent = 0
    public var clips: [ClipBlock] = []
}

/// A set's arrangement: tracks, their colours and clips on a time ruler.
public struct Arrangement: Sendable {
    public var path = "", creator = ""
    public var tempo = 0.0
    /// The last beat with anything on it.
    public var end = 0.0
    public var tracks: [TrackLane] = []
    public var clipCount = 0, noteCount = 0
    public var error: String?

    public init() {}

    public var hasContent: Bool { clipCount > 0 }

    /// Length in bars at 4/4 — for the caption; the grid is counted the same way.
    public var bars: Int { Int((end / 4.0).rounded(.up)) }

    /// A cap for the whole set: large projects have hundreds of thousands of notes, and the
    /// preview reduces them to a couple of pixels anyway.
    public static let maxNotes = 200_000

    /// Never throws; failures land in `error`, with whatever was parsed before them.
    public static func read(path: String) -> Arrangement {
        do {
            return parse(xml: try Gzip.readMaybeGzip(path: path), path: path)
        } catch {
            var a = Arrangement()
            a.path = path
            a.error = error.localizedDescription
            ArrangementParser.finish(&a)
            return a
        }
    }

    public static func parse(xml: Data, path: String = "") -> Arrangement {
        let parser = ArrangementParser()
        parser.arr.path = path
        let stream = ElementStream(onStart: { parser.start($0) }, onEnd: { parser.end($0) })
        parser.arr.error = stream.run(xml)
        ArrangementParser.finish(&parser.arr)
        return parser.arr
    }
}
