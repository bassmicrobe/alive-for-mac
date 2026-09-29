// Port of src/LiveLog.cs, macOS edition: `~/Library/Preferences/Ableton/Live <ver>/Log.txt`.
import Foundation

/// How one attempt to open a set ended.
public enum LoadResult: Sendable {
    /// The block started and is still being written — Live is loading right now.
    case running
    /// "Loaded document was created by …" — the document was read through in full.
    case loaded
    /// The block broke off: further on in the log there is another attempt, or the end of the file.
    case broke
}

/// One plugin Live was raising while opening a set.
public struct PluginLoad: Equatable, Sendable {
    public var name = ""
    public var kind: PluginKind = .vst3
    /// We saw the matching "Restored: name".
    public var restored = false
    /// We saw "Restore N failed: name" — the plugin refused, but Live survived.
    public var failed = false
    public var at = Date.distantPast

    public init() {}

    /// "VST3", "VST2" or "AU".
    public var format: String {
        switch kind {
        case .vst3: return "VST3"
        case .vst2: return "VST2"
        default: return "AU"
        }
    }

    /// Neither an answer nor an error: Live went into the plugin and never came back.
    public var isHung: Bool { !restored && !failed }
}

/// A block of the log from "Loading document …" to the next one just like it — exactly one
/// attempt to open one set, with the list of plugins raised along the way.
public struct LoadAttempt: Sendable {
    public var logPath = ""
    /// The settings folder name: "Live 11.3.35".
    public var liveVersion = ""
    /// The path exactly as Live wrote it.
    public var document = ""
    public var started = Date.distantPast
    public var lastEvent = Date.distantPast
    /// "Ableton Live 11.2.6" out of the Loaded document line.
    public var createdBy = ""
    public var result: LoadResult = .running
    public var plugins: [PluginLoad] = []
    /// Mac: Live's next start wrote "Detected a prior crash" right after this attempt broke off.
    public var priorCrashDetected: Date?

    public init() {}

    /// The plugin everything broke off on. It is necessarily the LAST record of the block and
    /// necessarily without a pair: Live died inside its code before it could finish writing the
    /// log, so there is physically nothing after it in the block.
    ///
    /// "The last" specifically, not "any one without a pair". A record also stays unpaired when
    /// a plugin introduced itself by one name and reported back under another
    /// ("Going to restore: SpaceCarver" … "Restored: Oppressor"); plugins from one build with a
    /// shared class prefix behave that way in sets that open perfectly well. Counting them as
    /// hung means accusing a healthy plugin.
    public var hung: PluginLoad? {
        guard result != .loaded, let last = plugins.last, last.isHung else { return nil }
        return last
    }

    public var restoredCount: Int { plugins.filter(\.restored).count }
    public var failures: [PluginLoad] { plugins.filter(\.failed) }

    /// The plugins Live refused, one entry per plugin however often the log repeats the
    /// complaint (a set with six copies of one plugin logs six identical failures per attempt):
    /// what the UI shows as ONE message with a collapsible list, never one alert per line.
    public var failureGroups: [PluginFailureGroup] {
        var order: [String] = []
        var groups: [String: PluginFailureGroup] = [:]
        for p in plugins where p.failed {
            let key = p.format + "|" + p.name.lowercased()
            if groups[key] == nil {
                groups[key] = PluginFailureGroup(name: p.name, format: p.format, count: 0)
                order.append(key)
            }
            groups[key]?.count += 1
        }
        return order.compactMap { groups[$0] }
    }
}

/// One plugin that failed to load, with how many times the log says so.
public struct PluginFailureGroup: Equatable, Identifiable, Sendable {
    public var name: String
    public var format: String
    public var count: Int

    public var id: String { format + "|" + name.lowercased() }
}

/// Live's own log. Nothing needs working out here — Live writes what we need itself, and writes
/// it before falling over:
///
///     2026-03-28T22:45:14.630680: info: Loading document "/Users/…/big.als"
///     …: info: Audio Unit v2: Going to restore: Serum
///     …: info: Audio Unit v2: Restored: Serum
///     …: info: Loaded document was created by Ableton Live 11.2.6
///
/// If Live dies inside a plugin, the last line of the block is a "Going to restore" with no
/// pair. That is the culprit's name, without a single launch. The log is cumulative and is not
/// rewritten between runs, so an attempt from a week ago is as visible as today's.
///
/// The Mac tags differ from Windows: `Audio Unit v2:`, `Audio Unit:`, `VST3:` / `Vst3:`,
/// `VST2:` and (for failures) `VST 2.4:`.
public enum LiveLog {
    static let loadingMark = "Loading document \""
    static let loadedMark = "Loaded document was created by "
    static let priorCrashMark = "Detected a prior crash"

    /// The logs of every Live install — from the one written to last back to the older ones.
    /// `prefsFolders` are `~/Library/Preferences/Ableton/Live …` folders (any order).
    public static func files(prefsFolders: [String]) -> [LiveLogFile] {
        let fm = FileManager.default
        var found: [LiveLogFile] = []
        for dir in prefsFolders {
            let log = dir + "/Log.txt"
            if fm.fileExists(atPath: log) {
                found.append(LiveLogFile(path: log, version: (dir as NSString).lastPathComponent))
            }
        }
        return found.sorted { $0.written > $1.written }
    }

    /// The same for this machine's Live installs.
    public static func files(home: String = NSHomeDirectory()) -> [LiveLogFile] {
        files(prefsFolders: LiveEnvironment.findPrefsFolders(home: home))
    }

    /// The most recent attempt to open this particular set — across every installed version of
    /// Live at once: several versions usually live on a machine, and which of them broke on a
    /// project the user neither remembers nor is obliged to know.
    public static func lastAttempt(for alsPath: String, in files: [LiveLogFile]) -> LoadAttempt? {
        var best: LoadAttempt?
        for f in files {
            guard let a = f.lastAttempt(for: alsPath) else { continue }
            if best == nil || a.started > best!.started { best = a }
        }
        return best
    }

    // MARK: parsing

    /// Parses already-read lines of the log into attempts. A function of its own rather than the
    /// guts of `LiveLogFile`: it serves both the tail of a file while watching and a whole file
    /// for a one-off diagnosis.
    public static func parse(lines: [String], logPath: String = "", version: String = "") -> [LoadAttempt] {
        var attempts: [LoadAttempt] = []
        var stamps = StampParser()

        for raw in lines {
            guard !raw.isEmpty, let (at, text) = payload(of: raw, stamps: &stamps) else { continue }

            if text.hasPrefix(loadingMark) {
                // A new block closes the previous one: if it never said "Loaded document", it
                // never loaded.
                close(&attempts)
                var a = LoadAttempt()
                a.logPath = logPath
                a.liveVersion = version
                a.document = quoted(text, from: loadingMark.count)
                a.started = at
                a.lastEvent = at
                attempts.append(a)
                continue
            }
            guard !attempts.isEmpty else { continue }
            let i = attempts.count - 1

            if text.contains(priorCrashMark) {
                if attempts[i].result != .loaded, attempts[i].priorCrashDetected == nil {
                    attempts[i].priorCrashDetected = at
                }
                continue
            }
            attempts[i].lastEvent = at

            if text.hasPrefix(loadedMark) {
                attempts[i].createdBy = String(text.dropFirst(loadedMark.count)).trimmingCharacters(in: .whitespaces)
                attempts[i].result = .loaded
                continue
            }
            guard let event = pluginEvent(text) else { continue }
            switch event.what {
            case .going:
                var p = PluginLoad()
                p.kind = event.kind
                p.name = event.name
                p.at = at
                attempts[i].plugins.append(p)
            case .restored: pending(&attempts[i], event, restored: true, failed: false)
            case .failed: pending(&attempts[i], event, restored: false, failed: true)
            }
        }
        return attempts
    }

    /// The block ended and there was no "Loaded document" — it broke off. While the block is
    /// the last one in the file this may still be "Live is loading right now"; the caller
    /// decides that (see `LiveLogFile.settle`).
    private static func close(_ attempts: inout [LoadAttempt]) {
        guard let i = attempts.indices.last, attempts[i].result == .running else { return }
        attempts[i].result = .broke
    }

    /// Closes the last unclosed record with this name. By name rather than "the last one at
    /// all": Live has nested restores (a plugin inside a rack), and the order of closing then
    /// does not match the order of opening.
    private static func pending(_ a: inout LoadAttempt, _ e: PluginEvent, restored: Bool, failed: Bool) {
        for i in a.plugins.indices.reversed() {
            guard a.plugins[i].isHung, a.plugins[i].name == e.name else { continue }
            a.plugins[i].restored = restored
            a.plugins[i].failed = failed
            return
        }
        // No pair: the log was read starting from the middle of a block. The record is
        // valuable all the same — this plugin got through loading.
        var orphan = PluginLoad()
        orphan.kind = e.kind
        orphan.name = e.name
        orphan.restored = restored
        orphan.failed = failed
        a.plugins.append(orphan)
    }

    private enum PluginWhat { case going, restored, failed }
    private struct PluginEvent { var kind: PluginKind; var what: PluginWhat; var name: String }

    /// "Audio Unit v2: Going to restore: X", "VST3: Restored: X", "VST 2.4: Restore 1 failed: X".
    private static func pluginEvent(_ text: String) -> PluginEvent? {
        let going = ": Going to restore: ", restored = ": Restored: "
        if let r = text.range(of: going), let kind = kind(ofTag: text[..<r.lowerBound]) {
            return PluginEvent(kind: kind, what: .going,
                               name: String(text[r.upperBound...]).trimmingCharacters(in: .whitespaces))
        }
        if let r = text.range(of: restored), let kind = kind(ofTag: text[..<r.lowerBound]) {
            return PluginEvent(kind: kind, what: .restored,
                               name: String(text[r.upperBound...]).trimmingCharacters(in: .whitespaces))
        }
        // "<tag>: Restore 1 failed: Dist COLDFIRE" — the attempt number is of no use to us.
        if let r = text.range(of: ": Restore "),
           let f = text.range(of: " failed: ", range: r.upperBound..<text.endIndex),
           let kind = kind(ofTag: text[..<r.lowerBound]) {
            return PluginEvent(kind: kind, what: .failed,
                               name: String(text[f.upperBound...]).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// The format a log tag names; nil for anything that is not a plugin format (the text before
    /// the marker is a whole message then, not a tag).
    static func kind(ofTag tag: Substring) -> PluginKind? {
        guard tag.count <= 24, !tag.contains(":") else { return nil }
        let t = tag.lowercased()
        if t.hasPrefix("audio unit") { return .audioUnit }
        if t.hasPrefix("vst3") { return .vst3 }
        if t.hasPrefix("vst") { return .vst2 }        // "VST2", "VST 2.4"
        return nil
    }

    /// "2026-08-24T15:15:42.939602: info: Loading document "…"" → the record's timestamp and
    /// text. Lines without such a header are the continuation of the previous record (Live wraps
    /// MIDI device lists over several lines) and never carry markers.
    static func payload(of line: String, stamps: inout StampParser) -> (Date, String)? {
        guard line.utf8.count > 22, let (at, length) = stamps.parse(line) else { return nil }
        // ": info: " / ": error: " right after the stamp (19 characters, or 26 with microseconds).
        let u = line.utf8
        guard u.count > length else { return nil }
        let start = u.index(u.startIndex, offsetBy: length)
        let rest = line[start...]
        for mark in [": info: ", ": error: "] where rest.hasPrefix(mark) {
            return (at, String(rest.dropFirst(mark.count)))
        }
        return nil
    }

    private static func quoted(_ text: String, from: Int) -> String {
        let body = text.dropFirst(from)
        guard let close = body.firstIndex(of: "\"") else { return String(body) }
        return String(body[..<close])
    }

    // MARK: comparing paths

    /// Whether this is the same file. macOS volumes are case-insensitive by default and a name
    /// can be composed either way (NFC/NFD); `/tmp` is a symlink to `/private/tmp`.
    public static func samePath(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }

    static func normalize(_ p: String) -> String {
        guard !p.isEmpty else { return "" }
        var s = p.replacingOccurrences(of: "\\", with: "/")
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        s = resolvingSymlinks(s)
        return s.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Symlinks are resolved on the deepest folder that exists, so a path that is gone (a probe
    /// already deleted) still compares equal through `/tmp` → `/private/tmp`.
    private static func resolvingSymlinks(_ path: String) -> String {
        let fm = FileManager.default
        var head = path
        var tail: [String] = []
        while head.count > 1, !fm.fileExists(atPath: head) {
            tail.insert((head as NSString).lastPathComponent, at: 0)
            head = (head as NSString).deletingLastPathComponent
        }
        var resolved = URL(fileURLWithPath: head).resolvingSymlinksInPath().path
        for c in tail { resolved = (resolved as NSString).appendingPathComponent(c) }
        return resolved
    }
}

/// Fast "yyyy-MM-ddTHH:mm:ss.ffffff" parsing: the minute is converted once and cached, and the
/// seconds are added by hand (a log holds hundreds of thousands of lines).
struct StampParser {
    private var minuteKey: Substring = ""
    private var minuteDate = Date.distantPast
    private static let calendar = Calendar(identifier: .gregorian)

    /// The stamp's date and how many bytes it takes (19, or 26 with the fraction).
    mutating func parse(_ line: String) -> (Date, Int)? {
        let b = Array(line.utf8.prefix(26))
        guard b.count >= 19, b[4] == 0x2D, b[7] == 0x2D, b[10] == 0x54, b[13] == 0x3A, b[16] == 0x3A else { return nil }
        func num(_ a: Int, _ n: Int) -> Int? {
            var v = 0
            for i in a..<(a + n) {
                guard i < b.count, b[i] >= 0x30, b[i] <= 0x39 else { return nil }
                v = v * 10 + Int(b[i] - 0x30)
            }
            return v
        }
        guard let sec = num(17, 2) else { return nil }
        let key = line.prefix(16)
        if key != minuteKey {
            guard let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2), let h = num(11, 2), let mi = num(14, 2)
            else { return nil }
            var c = DateComponents()
            c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = 0
            guard let date = Self.calendar.date(from: c) else { return nil }
            minuteKey = key
            minuteDate = date
        }
        var frac = 0.0
        var length = 19
        if b.count >= 26, b[19] == 0x2E, let f = num(20, 6) { frac = Double(f) / 1_000_000; length = 26 }
        return (minuteDate.addingTimeInterval(Double(sec) + frac), length)
    }
}

/// One Log.txt that can be read whole and read on as Live writes into it. The rescue sheet
/// waits to see how a probe ends and has to show the answer at once rather than chew through
/// nine megabytes on every tick of the timer.
public final class LiveLogFile {
    public let path: String
    public let version: String

    /// Which byte to read on from. It stands not at the end of the file but at the start of the
    /// last unclosed "Loading document" block: the block is parsed whole every time, or an
    /// attempt that began between ticks would arrive without its first plugins.
    private var offset: Int64 = 0

    /// How long the log has to stay silent before a load counts as aborted. Generous on
    /// purpose: between "Going to restore" and "Restored" a heavy plugin leaves up to ten
    /// seconds of silence, and a hasty threshold would name a healthy plugin guilty.
    static let silence: TimeInterval = 45

    /// How many bytes of the log to read at a time. Log.txt is cumulative and reaches tens of
    /// megabytes; 32 is a cap both for a one-off diagnosis and against a file grown indecently.
    static let maxRead: Int64 = 32 * 1024 * 1024

    private static let openBlock = ": info: Loading document \""

    init(path: String, version: String) {
        self.path = path
        self.version = version
    }

    public var written: Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
    }

    public var length: Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber
        return size?.int64Value ?? 0
    }

    /// Start watching from the current end — the past is of no interest in a probe.
    public func skipToEnd() { offset = length }

    /// The most recent attempt to open this set in the whole file. Files that cannot mention the
    /// set are skipped without parsing (tens of megabytes across all Live versions).
    public func lastAttempt(for alsPath: String) -> LoadAttempt? {
        var best: LoadAttempt?
        for a in all(mentioning: alsPath) where LiveLog.samePath(a.document, alsPath) {
            if best == nil || a.started >= best!.started { best = a }
        }
        return best
    }

    /// Every attempt in the whole file (its last 32 MB).
    public func all() -> [LoadAttempt] { all(mentioning: nil) }

    private func all(mentioning alsPath: String?) -> [LoadAttempt] {
        read(from: 0, advance: false, mentioning: alsPath).attempts
    }

    /// What has been appended since last time. The last block may not be finished — it comes
    /// back `.running`, and next time it arrives again, whole.
    public func readNew() -> [LoadAttempt] {
        let r = read(from: offset, advance: true, mentioning: nil)
        offset = r.next
        return r.attempts
    }

    /// Crash-recovery folders Live left in `Crash/` next to the log: their names start with the
    /// time of the *next* start ("2026_04_17__17_53_34_BaseFiles").
    public func crashDates() -> [Date] {
        let dir = (path as NSString).deletingLastPathComponent + "/Crash"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy_MM_dd__HH_mm_ss"
        return Set(names.compactMap { $0.count >= 20 ? f.date(from: String($0.prefix(20))) : nil }).sorted()
    }

    private func read(from start: Int64, advance: Bool, mentioning alsPath: String?)
        -> (attempts: [LoadAttempt], next: Int64) {
        var from = start
        if length < from { from = 0 }       // trimmed or reinstalled: start over
        guard let h = FileHandle(forReadingAtPath: path) else { return ([], start) }
        defer { try? h.close() }
        guard let endOffset = try? h.seekToEnd() else { return ([], start) }
        let end = Int64(endOffset)
        var size = end - from
        if size < 0 { size = 0 }
        if size > Self.maxRead { from = end - Self.maxRead; size = Self.maxRead }
        guard (try? h.seek(toOffset: UInt64(from))) != nil,
              let data = try? h.read(upToCount: Int(size)) else { return ([], start) }
        let fileEnd = from + Int64(data.count)

        if let alsPath, !Self.mayMention(data, alsPath) { return ([], fileEnd) }

        // Split by bytes: the exact offset of a line's start is needed to come back to an
        // unclosed block, and it cannot be recomputed from the decoded string's length — Live's
        // log is UTF-8 and full of non-ASCII project names. Endings are lone LFs; a trailing CR
        // is stripped just in case.
        var lines: [String] = []
        var lastOpenBlock: Int64 = -1
        let mark = Array(Self.openBlock.utf8)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let buf = raw.bindMemory(to: UInt8.self)
            var s = 0
            for i in 0...buf.count {
                if i < buf.count, buf[i] != 0x0A { continue }
                var e = i
                if e > s, buf[e - 1] == 0x0D { e -= 1 }
                if e > s {
                    let slice = UnsafeBufferPointer(rebasing: buf[s..<e])
                    if Self.contains(slice, mark) { lastOpenBlock = from + Int64(s) }
                    lines.append(String(decoding: slice, as: UTF8.self))
                }
                s = i + 1
            }
        }

        var attempts = LiveLog.parse(lines: lines, logPath: path, version: version)
        settle(&attempts)
        let tailOpen = attempts.last?.result == .running && lastOpenBlock >= 0
        return (attempts, advance && tailOpen ? lastOpenBlock : fileEnd)
    }

    /// Parsing always leaves the last block of a file as running: nothing closes it — the next
    /// "Loading document" is not there yet. If nobody has written to the log for a long time,
    /// Live is not loading but not writing at all — the block broke off.
    private func settle(_ attempts: inout [LoadAttempt]) {
        guard let i = attempts.indices.last, attempts[i].result == .running else { return }
        let w = written
        if w != .distantPast, Date().timeIntervalSince(w) > Self.silence { attempts[i].result = .broke }
    }

    /// Whether the chunk can hold the set's path: its file name, composed either way.
    private static func mayMention(_ data: Data, _ alsPath: String) -> Bool {
        let name = (alsPath as NSString).lastPathComponent
        for variant in [name.precomposedStringWithCanonicalMapping, name.decomposedStringWithCanonicalMapping] {
            let needle = Array(variant.utf8)
            if data.withUnsafeBytes({ contains($0.bindMemory(to: UInt8.self), needle) }) { return true }
        }
        return false
    }

    static func contains(_ hay: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, let base = hay.baseAddress, hay.count >= needle.count else { return false }
        return needle.withUnsafeBufferPointer { n in
            memmem(base, hay.count, n.baseAddress!, n.count) != nil
        }
    }
}
