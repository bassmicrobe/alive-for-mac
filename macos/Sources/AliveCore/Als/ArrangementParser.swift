// Port of src/Arrangement.cs (Parse, CloseClip, Palette, Finish)
import Foundation

/// The depth-aware state machine over the element stream. Session clips live in ClipSlotList
/// and never reach the ruler, so only what is inside `ArrangerAutomation` counts.
final class ArrangementParser {
    var arr = Arrangement()

    private var trackDepth = -1
    private var track: TrackLane?
    private var trackNameDepth = -1
    private var arrangerDepth = -1
    private var clipDepth = -1
    private var clip: ClipBlock?
    private var loopDepth = -1
    private var keyTrackDepth = -1
    private var keyNoteStart = 0
    private var mainTrackDepth = -1
    private var tempoDepth = -1
    private var tempoSeen = false

    // MARK: events

    func end(_ d: Int) {
        if keyTrackDepth >= 0 && d <= keyTrackDepth { keyTrackDepth = -1 }
        if loopDepth >= 0 && d <= loopDepth { loopDepth = -1 }
        if clipDepth >= 0 && d <= clipDepth {
            closeClip()
            clip = nil; clipDepth = -1
        }
        if arrangerDepth >= 0 && d <= arrangerDepth { arrangerDepth = -1 }
        if trackNameDepth >= 0 && d <= trackNameDepth { trackNameDepth = -1 }
        if trackDepth >= 0 && d <= trackDepth { closeTrack(); track = nil; trackDepth = -1 }
        if mainTrackDepth >= 0 && d <= mainTrackDepth { mainTrackDepth = -1 }
        if tempoDepth >= 0 && d <= tempoDepth { tempoDepth = -1 }
    }

    func start(_ e: XMLTag) {
        openContext(e)
        if track != nil, e.depth == trackDepth + 1 { trackChild(e) }
        if trackNameDepth >= 0, e.name == "EffectiveName", e.depth == trackNameDepth + 1,
           let n = e.value, !n.isEmpty { track?.name = n }
        if clip != nil, e.depth == clipDepth + 1 { clipChild(e) }
        if loopDepth >= 0, clip != nil, e.depth == loopDepth + 1 { loopChild(e) }
        if tempoDepth >= 0, e.name == "Manual", e.depth == tempoDepth + 1 {
            let t = e.double(0)
            if t > 0 { arr.tempo = t; tempoSeen = true }
        }
    }

    private func openContext(_ e: XMLTag) {
        switch e.name {
        case "Ableton": arr.creator = e.attrs["Creator"] ?? ""
        case "AudioTrack", "MidiTrack", "GroupTrack":
            var t = TrackLane()
            t.isMidi = e.name == "MidiTrack"
            t.isGroup = e.name == "GroupTrack"
            t.id = Int(e.attrs["Id"] ?? "") ?? -1
            track = t; trackDepth = e.depth
        case "MainTrack", "MasterTrack": mainTrackDepth = e.depth
        case "ArrangerAutomation":
            if track != nil { arrangerDepth = e.depth }
        case "AudioClip", "MidiClip":
            if arrangerDepth >= 0 && track != nil {
                var c = ClipBlock()
                c.isMidi = e.name == "MidiClip"
                clip = c; clipDepth = e.depth
            }
        case "Loop":
            if clip != nil && e.depth == clipDepth + 1 { loopDepth = e.depth }
        case "KeyTrack":
            if let c = clip { keyTrackDepth = e.depth; keyNoteStart = c.notes?.count ?? 0 }
        case "MidiNoteEvent": addNote(e)
        case "MidiKey": applyKey(e)   // the pitch arrives after the notes: <KeyTrack><Notes/><MidiKey/>
        case "Name":
            if Self.isTrack(e.parent) { trackNameDepth = e.depth }
        case "Tempo":
            if mainTrackDepth >= 0 && !tempoSeen { tempoDepth = e.depth }
        default: break
        }
    }

    private func trackChild(_ e: XMLTag) {
        switch e.name {
        case "Color", "ColorIndex": track?.color = Self.palette(e.int(-1))
        case "TrackGroupId": track?.groupId = e.int(-1)
        case "Freeze": track?.frozen = e.bool
        default: break
        }
    }

    private func clipChild(_ e: XMLTag) {
        switch e.name {
        case "CurrentStart": clip?.start = e.double(0)
        case "CurrentEnd": clip?.end = e.double(0)
        case "Name": clip?.name = e.value ?? ""
        case "Color", "ColorIndex": clip?.color = Self.palette(e.int(-1))
        case "Disabled": clip?.disabled = e.bool
        default: break
        }
    }

    private func loopChild(_ e: XMLTag) {
        switch e.name {
        case "LoopStart": clip?.loopStart = e.double(0)
        case "LoopEnd": clip?.loopEnd = e.double(0)
        case "StartRelative": clip?.startRelative = e.double(0)
        case "LoopOn": clip?.loopOn = e.bool
        default: break
        }
    }

    private func addNote(_ e: XMLTag) {
        guard clip != nil, keyTrackDepth >= 0, arr.noteCount < Arrangement.maxNotes else { return }
        var n = NoteEvent()
        n.time = Float(e.attrs["Time"].flatMap(Double.init) ?? 0)
        n.duration = Float(e.attrs["Duration"].flatMap(Double.init) ?? 0)
        n.velocity = UInt8(max(0, min(127, Int(e.attrs["Velocity"] ?? "") ?? 100)))
        var notes = clip?.notes ?? []
        clip?.notes = nil          // keep the array uniquely referenced: no O(n^2) copies
        notes.append(n)
        clip?.notes = notes
        arr.noteCount += 1
    }

    private func applyKey(_ e: XMLTag) {
        guard clip != nil, keyTrackDepth >= 0, let count = clip?.notes?.count else { return }
        let pitch = max(0, min(127, e.int(60)))
        for i in keyNoteStart..<count { clip?.notes?[i].pitch = UInt8(pitch) }
        if count > keyNoteStart {
            let lo = min(clip?.minPitch ?? pitch, pitch), hi = max(clip?.maxPitch ?? pitch, pitch)
            clip?.minPitch = lo
            clip?.maxPitch = hi
        }
    }

    // MARK: closing

    private func closeTrack() {
        if let t = track { arr.tracks.append(t) }
    }

    private func closeClip() {
        guard var c = clip, track != nil else { return }
        if c.end <= c.start { return }                       // a junk clip
        if c.maxPitch < c.minPitch { c.minPitch = 60; c.maxPitch = 60 }
        track?.clips.append(c)
        arr.clipCount += 1
        if c.end > arr.end { arr.end = c.end }
    }

    /// A colour number turned into "index in the 0..69 palette".
    ///
    /// Live 11 and 12 write `<Color Value="23"/>` — the palette index directly. Older sets write
    /// `<ColorIndex>`; for clips it matches the palette, for tracks it is shifted: across 4,300
    /// "a track and its clips" pairs the shift was exactly 140 (85%), and a separate block shows
    /// 218 (track 282 against clips at 64). Anything in no block is unknown — the colour is then
    /// taken from the track's clips.
    static func palette(_ raw: Int) -> Int {
        if raw < 0 { return -1 }
        if raw < LiveColors.count { return raw }
        if raw >= 218 && raw < 218 + LiveColors.count { return raw - 218 }
        if raw >= 140 && raw < 140 + LiveColors.count { return raw - 140 }
        return -1
    }

    static func isTrack(_ n: String) -> Bool {
        ["AudioTrack", "MidiTrack", "GroupTrack", "ReturnTrack", "MainTrack", "MasterTrack"].contains(n)
    }

    /// Indents by group nesting; fills missing track colours from the clips; minimum end of 4.
    static func finish(_ a: inout Arrangement) {
        var byId: [Int: Int] = [:]
        for (i, t) in a.tracks.enumerated() where t.id >= 0 && byId[t.id] == nil { byId[t.id] = i }

        // A track's indent = how many groups sit above it. GroupId refers to the group's Id.
        for i in a.tracks.indices {
            var depth = 0, guardCount = 0
            var cur = a.tracks[i]
            while cur.groupId >= 0, guardCount < 16, let p = byId[cur.groupId] {
                depth += 1; guardCount += 1
                cur = a.tracks[p]
            }
            a.tracks[i].indent = depth
        }

        // The track colour did not parse — take the most common colour of its clips: a clip
        // inherits the track colour by default.
        for i in a.tracks.indices where a.tracks[i].color < 0 && !a.tracks[i].clips.isEmpty {
            var hist: [Int: Int] = [:]
            for c in a.tracks[i].clips where c.color >= 0 { hist[c.color, default: 0] += 1 }
            if let best = hist.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) {
                a.tracks[i].color = best.key
            }
        }
        if a.end < 4 { a.end = 4 }
    }
}
