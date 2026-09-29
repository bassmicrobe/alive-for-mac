import XCTest
@testable import AliveCore

/// Synthetic Live for Mac log lines (the real ones hold project names and are not committed).
enum LogFx {
    static func line(_ time: String, _ text: String, level: String = "info") -> String {
        "2026-03-28T\(time): \(level): \(text)"
    }

    static let loading = { (t: String, path: String) in line(t, "Loading document \"\(path)\"") }
    static let going = { (t: String, tag: String, name: String) in line(t, "\(tag): Going to restore: \(name)") }
    static let restored = { (t: String, tag: String, name: String) in line(t, "\(tag): Restored: \(name)") }
    static let loaded = { (t: String) in line(t, "Loaded document was created by Ableton Live 11.2.6") }

    /// Writes `<dir>/Live <version>/Log.txt` and returns the prefs folder.
    @discardableResult
    static func writeLog(_ t: TempDir, version: String, lines: [String], age: TimeInterval = 0) -> String {
        let dir = t.mkdir("prefs/Live \(version)")
        let log = dir + "/Log.txt"
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: log))
        if age != 0 { t.setModified(log, Date().addingTimeInterval(-age)) }
        return dir
    }
}

final class LiveLogParseTests: XCTestCase {
    private let doc = "/Users/x/Song Project/Song.als"

    private func parse(_ lines: [String]) -> [LoadAttempt] { LiveLog.parse(lines: lines) }

    func testLoadedAttemptWithMacTags() {
        let a = parse([
            LogFx.loading("22:45:14.630680", doc),
            LogFx.going("22:45:15.000001", "Audio Unit v2", "Serum"),
            LogFx.restored("22:45:16.000001", "Audio Unit v2", "Serum"),
            LogFx.going("22:45:16.100000", "VST3", "Pro-Q 3"),
            LogFx.restored("22:45:17.000000", "VST3", "Pro-Q 3"),
            LogFx.loaded("22:45:18.500000"),
        ])
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].document, doc)
        XCTAssertEqual(a[0].result, .loaded)
        XCTAssertEqual(a[0].createdBy, "Ableton Live 11.2.6")
        XCTAssertEqual(a[0].plugins.map(\.name), ["Serum", "Pro-Q 3"])
        XCTAssertEqual(a[0].plugins.map(\.format), ["AU", "VST3"])
        XCTAssertEqual(a[0].restoredCount, 2)
        XCTAssertNil(a[0].hung)
        XCTAssertEqual(a[0].lastEvent.timeIntervalSince(a[0].started), 3.869, accuracy: 0.001)
    }

    func testBrokenAttemptNamesTheLastUnpairedPlugin() {
        let a = parse([
            LogFx.loading("10:00:00.000000", doc),
            LogFx.going("10:00:01.000000", "Audio Unit", "Good One"),
            LogFx.restored("10:00:02.000000", "Audio Unit", "Good One"),
            LogFx.going("10:00:03.000000", "Audio Unit v2", "Culprit AU"),
            LogFx.loading("10:05:00.000000", "/other.als"),
        ])
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a[0].result, .broke)
        XCTAssertEqual(a[0].hung?.name, "Culprit AU")
        XCTAssertEqual(a[0].hung?.format, "AU")
        XCTAssertEqual(a[1].result, .running)   // the last block is settled by the file, not the parser
    }

    func testVst2Tags() {
        let a = parse([
            LogFx.loading("10:00:00.000000", doc),
            LogFx.going("10:00:01.000000", "VST2", "Old Synth"),
            LogFx.line("10:00:02.000000", "VST 2.4: Restore 1 failed: OneKnob Pumper", level: "error"),
            LogFx.going("10:00:03.000000", "Vst3", "Odd Case"),
        ])
        XCTAssertEqual(a[0].plugins.count, 3)
        XCTAssertEqual(a[0].plugins[0].format, "VST2")
        XCTAssertEqual(a[0].failures.map(\.name), ["OneKnob Pumper"])   // an orphan: log started mid-block
        XCTAssertEqual(a[0].plugins[2].format, "VST3")
        XCTAssertEqual(a[0].hung?.name, "Odd Case")
    }

    func testRefusedPluginPairsByNameAndIsNotHung() {
        let a = parse([
            LogFx.loading("10:00:00.000000", doc),
            LogFx.going("10:00:01.000000", "Audio Unit", "SSL Native Bus Compressor v6"),
            LogFx.line("10:00:02.000000", "Audio Unit: Restore 1 failed: SSL Native Bus Compressor v6", level: "error"),
        ])
        XCTAssertEqual(a[0].plugins.count, 1)
        XCTAssertTrue(a[0].plugins[0].failed)
        XCTAssertNil(a[0].hung)
        XCTAssertEqual(a[0].failures.count, 1)
    }

    func testRenamedPluginInLoadedSetIsNotAccused() {
        // A plugin that introduced itself by one name and restored under another must not count
        // as hung in a set that loaded fine.
        let a = parse([
            LogFx.loading("10:00:00.000000", doc),
            LogFx.going("10:00:01.000000", "VST3", "SpaceCarver"),
            LogFx.restored("10:00:02.000000", "VST3", "Oppressor"),
            LogFx.loaded("10:00:03.000000"),
        ])
        XCTAssertNil(a[0].hung)
        XCTAssertEqual(a[0].result, .loaded)
    }

    func testNestedRestoresCloseByName() {
        let a = parse([
            LogFx.loading("10:00:00.000000", doc),
            LogFx.going("10:00:01.000000", "VST3", "Outer"),
            LogFx.going("10:00:01.100000", "VST3", "Inner"),
            LogFx.restored("10:00:02.000000", "VST3", "Outer"),
            LogFx.restored("10:00:02.500000", "VST3", "Inner"),
            LogFx.loaded("10:00:03.000000"),
        ])
        XCTAssertEqual(a[0].restoredCount, 2)
        XCTAssertEqual(a[0].plugins.count, 2)
    }

    func testContinuationAndForeignLinesAreIgnored() {
        let a = parse([
            LogFx.loading("10:00:00.000000", doc),
            LogFx.line("10:00:00.500000", "AMidiIO: Midi Devices: "),
            "  MidiInDevice [Name=\"Peak\", Track=true]",
            "  MidiInDevice [Name=\"info: Loading document \\\"x\\\"\"]",
            LogFx.line("10:00:01.000000", "Error reading \"/Volumes/RAID/a.wav\"", level: "error"),
            "garbage",
            LogFx.going("10:00:02.000000", "Audio Unit v2", "Dist: Plugin Name"),
        ])
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].plugins.map(\.name), ["Dist: Plugin Name"])   // a colon inside the name survives
    }

    func testRepeatedRefusalsAreAggregatedPerPlugin() {
        // Six copies of one plugin and one other refusal in a single attempt, the way Live logs them.
        var lines = [LogFx.loading("10:00:00.000000", doc)]
        for i in 0..<6 {
            let t = String(format: "10:00:%02d.000000", i + 1)
            lines.append(LogFx.going(t, "Audio Unit", "SSL Native Bus Compressor v6"))
            lines.append(LogFx.line(t, "Audio Unit: Restore 1 failed: SSL Native Bus Compressor v6", level: "error"))
        }
        lines.append(LogFx.going("10:00:20.000000", "VST 2.4", "OneKnob Pumper"))
        lines.append(LogFx.line("10:00:21.000000", "VST 2.4: Restore 1 failed: OneKnob Pumper", level: "error"))
        lines.append(LogFx.going("10:00:22.000000", "Audio Unit", "ssl native bus compressor v6"))   // other case: same plugin
        lines.append(LogFx.line("10:00:23.000000", "Audio Unit: Restore 1 failed: ssl native bus compressor v6", level: "error"))
        lines.append(LogFx.loaded("10:00:30.000000"))

        let a = parse(lines)[0]
        XCTAssertEqual(a.failures.count, 8, "eight raw complaints in the log")
        let groups = a.failureGroups
        XCTAssertEqual(groups.count, 2, "…but two plugins")
        XCTAssertEqual(groups[0].name, "SSL Native Bus Compressor v6")
        XCTAssertEqual(groups[0].format, "AU")
        XCTAssertEqual(groups[0].count, 7)
        XCTAssertEqual(groups[1].name, "OneKnob Pumper")
        XCTAssertEqual(groups[1].count, 1)
        XCTAssertEqual(Set(groups.map(\.id)).count, 2)
        XCTAssertTrue(parse([LogFx.loading("10:00:00.000000", doc), LogFx.loaded("10:00:01.000000")])[0].failureGroups.isEmpty)
    }

    func testTagClassification() {
        XCTAssertEqual(LiveLog.kind(ofTag: "Audio Unit v2"), .audioUnit)
        XCTAssertEqual(LiveLog.kind(ofTag: "Audio Unit"), .audioUnit)
        XCTAssertEqual(LiveLog.kind(ofTag: "VST3"), .vst3)
        XCTAssertEqual(LiveLog.kind(ofTag: "Vst3"), .vst3)
        XCTAssertEqual(LiveLog.kind(ofTag: "VST2"), .vst2)
        XCTAssertEqual(LiveLog.kind(ofTag: "VST 2.4"), .vst2)
        XCTAssertNil(LiveLog.kind(ofTag: "Default App"))
        XCTAssertNil(LiveLog.kind(ofTag: "a: VST3"))
        XCTAssertNil(LiveLog.kind(ofTag: "this is a very long message that only ends with VST"))
    }

    func testPriorCrashLineMarksTheBrokenAttempt() {
        let a = parse([
            LogFx.loading("10:00:00.000000", doc),
            LogFx.going("10:00:01.000000", "VST3", "Boom"),
            LogFx.line("10:30:00.000000", "Default App: Detected a prior crash"),
            LogFx.loading("10:31:00.000000", doc),
            LogFx.loaded("10:31:05.000000"),
            LogFx.line("11:00:00.000000", "Default App: Detected a prior crash"),   // not this one: it loaded
        ])
        XCTAssertNotNil(a[0].priorCrashDetected)
        XCTAssertEqual(a[0].result, .broke)
        XCTAssertNil(a[1].priorCrashDetected)
        // The crash line does not count as activity inside the block.
        XCTAssertEqual(a[0].lastEvent.timeIntervalSince(a[0].started), 1, accuracy: 0.01)
    }

    func testStampsWithoutFractionAreAccepted() {
        let a = parse(["2026-03-28T10:00:00: info: Loading document \"/a.als\"",
                       "2026-03-28T10:00:07: info: Loaded document was created by Ableton Live 12.0"])
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].result, .loaded)
        XCTAssertEqual(a[0].lastEvent.timeIntervalSince(a[0].started), 7, accuracy: 0.001)
    }

    func testStampParserMatchesDateFormatter() {
        var p = StampParser()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        for s in ["2026-03-28T22:45:14.630680", "2026-03-28T22:45:59.999999", "2026-12-31T23:59:59.000001",
                  "2022-11-04T02:47:17.177599"] {
            let mine = p.parse(s + ": info: x")!.0
            let ref = f.date(from: s)!
            XCTAssertEqual(mine.timeIntervalSince1970, ref.timeIntervalSince1970, accuracy: 0.001, s)
        }
        XCTAssertNil(p.parse("not a stamp at all, really!"))
        XCTAssertNil(p.parse("2026-13-99Tzz:zz:zz.000000: info: x"))
    }
}

final class LiveLogFileTests: XCTestCase {
    private let doc = "/Users/x/Song Project/Song.als"

    func testFilesAreNewestWrittenFirst() throws {
        let t = makeTemp()
        let old = LogFx.writeLog(t, version: "11.3.35", lines: [LogFx.loading("10:00:00.000000", doc)], age: 86_400)
        let new = LogFx.writeLog(t, version: "12.0b20", lines: [LogFx.loading("10:00:00.000000", doc)])
        let empty = t.mkdir("prefs/Live 10.1.41")            // no Log.txt: skipped
        let files = LiveLog.files(prefsFolders: [old, empty, new])
        XCTAssertEqual(files.map(\.version), ["Live 12.0b20", "Live 11.3.35"])
    }

    func testLastAttemptAcrossVersionsPicksTheNewest() throws {
        let t = makeTemp()
        let a = LogFx.writeLog(t, version: "11.3.35", lines: [
            LogFx.loading("10:00:00.000000", doc), LogFx.loaded("10:00:05.000000"),
        ])
        let b = LogFx.writeLog(t, version: "12.0b20", lines: [
            LogFx.loading("12:00:00.000000", doc),
            LogFx.going("12:00:01.000000", "Audio Unit v2", "Serum"),
            LogFx.loading("12:10:00.000000", "/somewhere/else.als"),
        ])
        let attempt = LiveLog.lastAttempt(for: doc, in: LiveLog.files(prefsFolders: [a, b]))
        XCTAssertEqual(attempt?.liveVersion, "Live 12.0b20")
        XCTAssertEqual(attempt?.hung?.name, "Serum")
        XCTAssertNil(LiveLog.lastAttempt(for: "/never/opened.als", in: LiveLog.files(prefsFolders: [a, b])))
    }

    func testStaleRunningBlockBecomesBroken() throws {
        let t = makeTemp()
        let dir = LogFx.writeLog(t, version: "11.3.35", lines: [
            LogFx.loading("10:00:00.000000", doc), LogFx.going("10:00:01.000000", "VST3", "Slow"),
        ], age: 3600)
        XCTAssertEqual(LiveLog.files(prefsFolders: [dir])[0].lastAttempt(for: doc)?.result, .broke)

        let fresh = LogFx.writeLog(t, version: "12.0b20", lines: [
            LogFx.loading("10:00:00.000000", doc), LogFx.going("10:00:01.000000", "VST3", "Slow"),
        ])
        XCTAssertEqual(LiveLog.files(prefsFolders: [fresh])[0].lastAttempt(for: doc)?.result, .running)
    }

    func testReadNewReturnsTheOpenBlockWholeUntilItEnds() throws {
        let t = makeTemp()
        let dir = LogFx.writeLog(t, version: "11.3.35", lines: [
            LogFx.loading("09:00:00.000000", "/old.als"), LogFx.loaded("09:00:02.000000"),
        ])
        let file = LiveLog.files(prefsFolders: [dir])[0]
        file.skipToEnd()
        XCTAssertTrue(file.readNew().isEmpty)

        let log = dir + "/Log.txt"
        func append(_ lines: [String]) throws {
            let h = try FileHandle(forWritingTo: URL(fileURLWithPath: log))
            try h.seekToEnd()
            try h.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
            try h.close()
        }
        try append([LogFx.loading("10:00:00.000000", doc), LogFx.going("10:00:01.000000", "VST3", "A")])
        var got = file.readNew()
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got[0].result, .running)
        XCTAssertEqual(got[0].plugins.count, 1)

        try append([LogFx.restored("10:00:02.000000", "VST3", "A"), LogFx.loaded("10:00:03.000000")])
        got = file.readNew()
        XCTAssertEqual(got.count, 1, "the open block is re-read whole")
        XCTAssertEqual(got[0].result, .loaded)
        XCTAssertEqual(got[0].plugins.count, 1)
        XCTAssertEqual(got[0].restoredCount, 1)

        XCTAssertTrue(file.readNew().isEmpty, "a finished block is not returned again")
    }

    func testShrunkFileIsReadFromTheStart() throws {
        let t = makeTemp()
        let dir = LogFx.writeLog(t, version: "11.3.35", lines: (0..<50).map {
            LogFx.line("09:00:\(String(format: "%02d", $0)).000000", "Some noise line number \($0)")
        })
        let file = LiveLog.files(prefsFolders: [dir])[0]
        file.skipToEnd()
        try Data((LogFx.loading("10:00:00.000000", doc) + "\n" + LogFx.loaded("10:00:01.000000") + "\n").utf8)
            .write(to: URL(fileURLWithPath: dir + "/Log.txt"))
        XCTAssertEqual(file.readNew().first?.result, .loaded)
    }

    func testUtf8ProjectNamesAndCrLf() throws {
        let t = makeTemp()
        let jp = "/Users/x/日本語の曲 Project/夜.als"
        let dir = t.mkdir("prefs/Live 11.3.35")
        let text = [LogFx.loading("10:00:00.000000", jp), LogFx.loaded("10:00:01.000000")].joined(separator: "\r\n")
        try Data(text.utf8).write(to: URL(fileURLWithPath: dir + "/Log.txt"))
        let file = LiveLog.files(prefsFolders: [dir])[0]
        XCTAssertEqual(file.lastAttempt(for: jp)?.document, jp)
        // The same name decomposed (NFD) on disk still matches.
        XCTAssertNotNil(file.lastAttempt(for: jp.decomposedStringWithCanonicalMapping))
    }

    func testCrashFolderDates() throws {
        let t = makeTemp()
        let dir = LogFx.writeLog(t, version: "11.3.35", lines: [LogFx.loading("10:00:00.000000", doc)])
        t.mkdir("prefs/Live 11.3.35/Crash/2026_04_17__17_53_34_BaseFiles")
        t.write("prefs/Live 11.3.35/Crash/2026_04_17__17_53_34_CrashRecoveryInfo.cfg")
        t.write("prefs/Live 11.3.35/Crash/notes.txt")
        let dates = LiveLog.files(prefsFolders: [dir])[0].crashDates()
        XCTAssertEqual(dates.count, 1)
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: dates[0])
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2026, 4, 17, 17, 53, 34])
    }

    func testSamePathIgnoresCaseSlashSymlinkAndNormalization() throws {
        XCTAssertTrue(LiveLog.samePath("/Users/X/Song.als", "/users/x/song.als"))
        XCTAssertTrue(LiveLog.samePath("/Users/x/Song Project/", "/Users/x/Song Project"))
        XCTAssertTrue(LiveLog.samePath("/tmp/alive-none/a.als", "/private/tmp/alive-none/a.als"))
        XCTAssertTrue(LiveLog.samePath("/a/é.als", "/a/e\u{301}.als"))
        XCTAssertFalse(LiveLog.samePath("/a/b.als", "/a/c.als"))
        XCTAssertFalse(LiveLog.samePath("", "/a"))
    }
}
