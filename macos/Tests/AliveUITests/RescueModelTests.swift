import AliveCore
import CryptoKit
import XCTest
@testable import AliveUI

/// Sets shaped like Live's: one tag per line, so the patchers see one node per line.
enum UIFixture {
    static func vst3(_ name: String, _ id: Int) -> String {
        let uid = (0..<4).map { "<Fields.\($0) Value=\"\($0 == 0 ? id : 7)\" />" }.joined()
        return "<PluginDevice><PluginDesc><Vst3PluginInfo Id=\"0\"><Name Value=\"\(name)\" /><Uid>\(uid)</Uid>"
            + "</Vst3PluginInfo></PluginDesc></PluginDevice>"
    }

    static func au(_ name: String, sub: Int) -> String {
        "<PluginDevice><PluginDesc><AuPluginInfo Id=\"0\"><ComponentType Value=\"1635085670\" />"
            + "<ComponentSubType Value=\"\(sub)\" /><ComponentManufacturer Value=\"1349087086\" />"
            + "<Name Value=\"\(name)\" /><Manufacturer Value=\"Acme\" /></AuPluginInfo></PluginDesc></PluginDevice>"
    }

    static func sampleRef(rel: String, abs: String, type: Int) -> String {
        "<SampleRef><FileRef><RelativePathType Value=\"\(type)\" /><RelativePath Value=\"\(rel)\" />"
            + "<Path Value=\"\(abs)\" /><Type Value=\"2\" /><LivePackName Value=\"\" /><LivePackId Value=\"\" />"
            + "<OriginalFileSize Value=\"1\" /></FileRef></SampleRef>"
    }

    static func xml(devices: [String] = [], refs: [String] = []) -> String {
        let body = "<Ableton Creator=\"Ableton Live 12.0\"><LiveSet><Tracks><AudioTrack Id=\"1\">"
            + devices.joined() + refs.joined() + "</AudioTrack></Tracks></LiveSet></Ableton>"
        return body.replacingOccurrences(of: "><", with: ">\n<")
    }

    @discardableResult
    static func write(_ xml: String, to path: String) throws -> String {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Gzip.compress(Data(xml.utf8)).write(to: URL(fileURLWithPath: path))
        return path
    }

    static func sha(_ path: String) -> String {
        let d = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    static func scratch(_ label: String) throws -> String {
        let dir = NSTemporaryDirectory() + "alive-s6-ui-" + label + "-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// A box for callbacks that Swift treats as concurrent.
final class ChangeFlag: @unchecked Sendable {
    private(set) var value = 0
    func bump() { value += 1 }
}

/// A counter that background queues may bump.
final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func bump() { lock.lock(); n += 1; lock.unlock() }
}

final class RescueTextTests: XCTestCase {
    private var saved: LanguagePreference = .system

    override func setUp() {
        super.setUp()
        saved = Localizer.shared.preference
        Localizer.shared.preference = .en
    }

    override func tearDown() {
        Localizer.shared.preference = saved
        super.tearDown()
    }

    func testDescribeNamesUpToThreeThenCounts() {
        XCTAssertEqual(RescueText.describe([]), "nothing")
        XCTAssertEqual(RescueText.describe(["A"]), "A")
        XCTAssertEqual(RescueText.describe(["A", "B", "C"]), "A, B, C")
        XCTAssertEqual(RescueText.describe(["A", "B", "C", "D"]), "4 plugins")
        XCTAssertEqual(RescueStrings.plugins(1), "1 plugin")
        XCTAssertEqual(RescueStrings.plugins(0), "0 plugins")
    }

    func testRefusedPluginsAreOneLineHoweverOftenTheLogRepeatsThem() {
        var attempt = LoadAttempt()
        for i in 0..<40 {                                        // 40 identical complaints, one plugin
            var p = PluginLoad()
            p.name = "SSL Native Bus Compressor v6"
            p.kind = .audioUnit
            p.failed = true
            attempt.plugins.append(p)
            if i % 10 == 0 {
                var q = PluginLoad()
                q.name = "OneKnob Pumper"
                q.kind = .vst2
                q.failed = true
                attempt.plugins.append(q)
            }
        }
        let groups = attempt.failureGroups
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(RescueText.refusedSummary(groups), "2 plugins failed to load in that attempt")
        XCTAssertFalse(RescueText.refusedSummary(groups)!.contains("\n"))
        XCTAssertEqual(RescueText.refusedLine(groups[0]), "AU SSL Native Bus Compressor v6 ×40")
        XCTAssertNil(RescueText.refusedSummary([]))
    }

    func testStatusSentences() {
        XCTAssertEqual(RescueText.status(.started(round: 1, disabled: ["Serum"])),
                       "Probe 1: Serum disabled. Waiting for Live to open it…")
        XCTAssertEqual(RescueText.status(.loading(round: 2, restored: 1)),
                       "Probe 2: Live is loading it — 1 plugin restored so far…")
        XCTAssertTrue(RescueText.status(.notOpened(round: 3, stoppedInside: "Serum", left: 4))
            .contains("(Live stopped inside Serum)"))
        XCTAssertFalse(RescueText.status(.notOpened(round: 3, stoppedInside: nil, left: 4)).contains("stopped inside"))
        XCTAssertEqual(RescueText.status(.startFailed("boom")), "Could not start the probe: boom")
    }

    func testHintPriority() {
        func hint(usable: Bool = true, waiting: Bool = false, live: Bool = false, off: Int = 2) -> String {
            RescueText.hint(usable: usable, waiting: waiting, liveRunning: live, disabledCount: off, probeFileName: "S.alive-probe.als")
        }
        XCTAssertTrue(hint(waiting: true).hasPrefix("Live is opening the probe"))
        XCTAssertEqual(hint(usable: false), "")
        XCTAssertTrue(hint(live: true).hasPrefix("Close Ableton Live first"))
        XCTAssertTrue(hint(off: 0).hasPrefix("Untick"))
        XCTAssertTrue(hint().contains("S.alive-probe.als"))
    }

    func testJapaneseIsUsedWhenSelected() {
        Localizer.shared.preference = .ja
        XCTAssertEqual(RescueText.describe([]), "なし")
        XCTAssertTrue(RescueText.refusedSummary([PluginFailureGroup(name: "A", format: "AU", count: 3)])!.contains("1 個のプラグイン"))
    }
}

@MainActor
final class RescueModelTests: XCTestCase {
    private var scratch = ""
    private var app: AppModel!
    private var model: RescueModel!
    private var opened: [String] = []
    private var liveRunning = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = try UIFixture.scratch("rescue")
        app = try makeModel()
        Localizer.shared.preference = .en           // AppModel resets it from settings
        model = app.rescue
        opened = []
        liveRunning = false
        model.isLiveRunning = { [unowned self] in liveRunning }
        model.logFiles = { [] }
        model.openProbe = { [unowned self] in opened.append($0) }
        model.pollInterval = .seconds(3600)              // ticks are driven by hand
    }

    override func tearDown() {
        model.close()
        try? FileManager.default.removeItem(atPath: scratch)
        try? FileManager.default.removeItem(atPath: app.dataDir)
        Localizer.shared.preference = .system
        super.tearDown()
    }

    private func makeSet(devices: [String]) throws -> String {
        try UIFixture.write(UIFixture.xml(devices: devices), to: scratch + "/Song Project/Song.als")
    }

    private var threePlugins: [String] {
        [UIFixture.vst3("Serum", 1), UIFixture.vst3("Pro-Q 3", 2), UIFixture.au("RMX-1000", sub: 909_342_512)]
    }

    private func siblings() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: scratch + "/Song Project")) ?? []).sorted()
    }

    func testOpeningTouchesNothingOnDisk() async throws {
        let als = try makeSet(devices: threePlugins)
        let before = UIFixture.sha(als)
        await model.open(path: als)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.usable)
        XCTAssertEqual(model.targets.count, 3)
        XCTAssertEqual(model.checked.count, 3, "opens with every box ticked: nothing disabled yet")
        XCTAssertTrue(model.disabled.isEmpty)
        XCTAssertFalse(model.runEnabled, "nothing unticked, nothing to probe")
        XCTAssertEqual(siblings(), ["Song.als"], "showing the sheet creates no probe")
        XCTAssertEqual(RescueProbe.journal(dir: app.dataDir), [])
        XCTAssertEqual(UIFixture.sha(als), before)
        XCTAssertEqual(model.setName, "Song")
        XCTAssertEqual(model.runTitle, .open)
    }

    func testTheTitleNameIsObservable() async throws {
        // The sheet's title reads it outside the content closure: it must be tracked state.
        let changed = ChangeFlag()
        withObservationTracking { _ = model.setName } onChange: { changed.bump() }
        await model.open(path: try makeSet(devices: threePlugins))
        XCTAssertGreaterThan(changed.value, 0)
        XCTAssertEqual(model.setName, "Song")
        model.close()
        XCTAssertEqual(model.setName, "")
    }

    func testListEditingAndSuggestion() async throws {
        await model.open(path: try makeSet(devices: threePlugins))
        model.setAll(enabled: false)
        XCTAssertEqual(model.disabled.count, 3)
        XCTAssertTrue(model.runEnabled)
        model.setAll(enabled: true)
        model.toggle(model.targets[1])
        XCTAssertEqual(model.disabled.map(\.name), [model.targets[1].name])
        model.applySuggestion()
        XCTAssertEqual(model.disabled.count, 3, "with no log hint the first suggestion is everything")
    }

    func testProbeLifecycleWithManualAnswers() async throws {
        let als = try makeSet(devices: threePlugins)
        let before = UIFixture.sha(als)
        await model.open(path: als)
        model.setAll(enabled: false)

        await model.runProbe()
        let probe = scratch + "/Song Project/Song.alive-probe.als"
        XCTAssertEqual(opened, [probe])
        XCTAssertEqual(model.phase, .waiting)
        XCTAssertTrue(FileManager.default.fileExists(atPath: probe))
        XCTAssertEqual(RescueProbe.journal(dir: app.dataDir), [probe])
        XCTAssertFalse(model.runEnabled)
        guard case .started(let round, let names)? = model.status else { return XCTFail("\(String(describing: model.status))") }
        XCTAssertEqual(round, 1)
        XCTAssertEqual(names.count, 3)

        model.answer(opened: true)                              // opened with all three off
        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(FileManager.default.fileExists(atPath: probe), "the probe is removed after every answer")
        XCTAssertEqual(RescueProbe.journal(dir: app.dataDir), [])
        XCTAssertEqual(model.session?.working?.count, 3)
        XCTAssertEqual(model.disabled.count, 1, "the next suggestion is half of the suspects")
        XCTAssertEqual(model.notes.count, 3, "everything is still a suspect")
        XCTAssertEqual(model.runTitle, .next)

        // Drive it to a verdict: the first plugin is the culprit.
        let culprit = model.targets[0]
        var guardrail = 0
        while model.session?.isFinished == false, guardrail < 8 {
            guardrail += 1
            let off = Set(model.disabled.map(\.uid))
            await model.runProbe()
            model.answer(opened: off.contains(culprit.uid))
        }
        XCTAssertEqual(model.session?.verdict, .culprit)
        XCTAssertEqual(model.notes[culprit.uid], .breaksTheSet)
        XCTAssertNil(model.status, "the header shows the verdict")
        XCTAssertEqual(model.runTitle, .again)
        XCTAssertTrue(model.canSaveRescued)
        XCTAssertEqual(siblings(), ["Song.als"])
        XCTAssertEqual(UIFixture.sha(als), before)
    }

    func testSavingTheRescuedCopyNeverTouchesTheOriginal() async throws {
        let als = try makeSet(devices: threePlugins)
        let before = UIFixture.sha(als)
        await model.open(path: als)
        model.setAll(enabled: false)
        await model.runProbe()
        model.answer(opened: true)
        var guardrail = 0
        let culprit = model.targets[2]
        while model.session?.isFinished == false, guardrail < 8 {
            guardrail += 1
            let off = Set(model.disabled.map(\.uid))
            await model.runProbe()
            model.answer(opened: off.contains(culprit.uid))
        }
        await model.saveRescued()
        XCTAssertTrue(model.produced.hasSuffix("Song (rescued).als"))
        XCTAssertEqual(siblings(), ["Song (rescued).als", "Song.als"])
        XCTAssertEqual(UIFixture.sha(als), before)
        guard case .saved(let name, let disabled)? = model.status else { return XCTFail() }
        XCTAssertEqual(name, "Song (rescued).als")
        XCTAssertEqual(disabled, [culprit.name])
        XCTAssertEqual(RescueProbe.journal(dir: app.dataDir), [])
    }

    func testLiveComingAndGoingIsLearntFromWorkspaceNotifications() async throws {
        let centre = NotificationCenter()
        model.workspaceCenter = centre
        model.pollInterval = .milliseconds(5)            // would show any idle polling at once
        await model.open(path: try makeSet(devices: threePlugins))
        XCTAssertFalse(model.liveRunning)

        liveRunning = true                               // nothing announces it yet
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertFalse(model.liveRunning, "an idle sheet does not poll the process list")

        centre.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        for _ in 0..<100 where !model.liveRunning { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(model.liveRunning)

        liveRunning = false
        centre.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        for _ in 0..<100 where model.liveRunning { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(model.liveRunning)

        model.close()                                    // observers are gone with the sheet
        liveRunning = true
        centre.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(model.liveRunning)
    }

    func testLiveLogsAreReadOnlyWhileAProbeIsOut() async throws {
        let reads = LockedCounter()
        model.logFiles = { reads.bump(); return [] }
        model.pollInterval = .milliseconds(5)
        await model.open(path: try makeSet(devices: threePlugins))
        let afterOpen = reads.value
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(reads.value, afterOpen, "no polling while nothing is out")

        model.setAll(enabled: false)
        await model.runProbe()
        XCTAssertEqual(model.phase, .waiting)
        for _ in 0..<100 where reads.value == afterOpen { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertGreaterThan(reads.value, afterOpen, "the log is watched while waiting")

        model.answer(opened: true)
        XCTAssertEqual(model.phase, .ready)
        try await Task.sleep(nanoseconds: 60_000_000)          // let a tick in flight finish
        let settled = reads.value
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(reads.value, settled, "and not any more once the answer is in")
    }

    func testRunningLiveBlocksTheProbeUntilItIsClosed() async throws {
        await model.open(path: try makeSet(devices: threePlugins))
        model.setAll(enabled: false)
        XCTAssertTrue(model.runEnabled)
        liveRunning = true
        await model.tick()
        XCTAssertTrue(model.liveRunning)
        XCTAssertFalse(model.runEnabled)
        await model.runProbe()
        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(siblings(), ["Song.als"])
        liveRunning = false
        await model.tick()
        XCTAssertTrue(model.runEnabled)
    }

    func testClosingTheSheetRemovesTheProbe() async throws {
        await model.open(path: try makeSet(devices: threePlugins))
        model.setAll(enabled: false)
        await model.runProbe()
        XCTAssertEqual(siblings(), ["Song.alive-probe.als", "Song.als"])
        model.close()
        XCTAssertEqual(siblings(), ["Song.als"])
        XCTAssertEqual(RescueProbe.journal(dir: app.dataDir), [])
        XCTAssertEqual(model.phase, .idle)
    }

    func testClosingWhileTheProbeIsBeingWrittenLeavesNothingBehind() async throws {
        await model.open(path: try makeSet(devices: threePlugins))
        model.setAll(enabled: false)
        let run = Task { await model.runProbe() }
        await Task.yield()                                      // runProbe is now waiting for the write
        XCTAssertEqual(model.phase, .preparing)
        model.close()
        await run.value
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(siblings(), ["Song.als"], "the probe written after close() is removed again")
        XCTAssertEqual(RescueProbe.journal(dir: app.dataDir), [])
        XCTAssertTrue(opened.isEmpty)
    }

    func testAnExistingProbeNamedFileIsNotTouchedByARun() async throws {
        let als = try makeSet(devices: threePlugins)
        let mine = scratch + "/Song Project/Song.alive-probe.als"
        try Data("mine".utf8).write(to: URL(fileURLWithPath: mine))
        await model.open(path: als)
        model.setAll(enabled: false)
        await model.runProbe()
        XCTAssertEqual(model.phase, .waiting)
        XCTAssertEqual(opened.count, 1)
        XCTAssertNotEqual(opened.first, mine)
        XCTAssertEqual(model.probeFileName, (opened.first! as NSString).lastPathComponent, "the sheet names the real probe")
        model.close()
        XCTAssertEqual(try String(contentsOfFile: mine), "mine")
        XCTAssertEqual(siblings(), ["Song.alive-probe.als", "Song.als"])
    }

    func testNeverOpenedProbeIsGivenUp() async throws {
        await model.open(path: try makeSet(devices: threePlugins))
        model.setAll(enabled: false)
        model.giveUpAfter = -1
        await model.runProbe()
        await model.tick()                                            // no log entry, Live not running
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.status, .neverOpened)
        XCTAssertEqual(siblings(), ["Song.als"])
    }

    func testLogVerdictIsPickedUpAutomatically() async throws {
        let als = try makeSet(devices: threePlugins)
        let prefs = scratch + "/prefs/Live 11.3.35"
        try FileManager.default.createDirectory(atPath: prefs, withIntermediateDirectories: true)
        let log = prefs + "/Log.txt"
        try Data("2026-03-28T09:00:00.000000: info: Default App: started\n".utf8).write(to: URL(fileURLWithPath: log))
        model.logFiles = { LiveLog.files(prefsFolders: [prefs]) }

        await model.open(path: als)
        model.setAll(enabled: false)
        await model.runProbe()
        let probe = scratch + "/Song Project/Song.alive-probe.als"

        let h = try FileHandle(forWritingTo: URL(fileURLWithPath: log))
        try h.seekToEnd()
        try h.write(contentsOf: Data(("2026-03-28T10:00:00.000000: info: Loading document \"\(probe)\"\n"
            + "2026-03-28T10:00:01.000000: info: Audio Unit v2: Going to restore: RMX-1000\n").utf8))
        await model.tick()
        XCTAssertEqual(model.phase, .waiting)
        XCTAssertEqual(model.status, .loading(round: 1, restored: 0))

        try h.write(contentsOf: Data(("2026-03-28T10:00:02.000000: info: Audio Unit v2: Restored: RMX-1000\n"
            + "2026-03-28T10:00:03.000000: info: Loaded document was created by Ableton Live 11.2.6\n").utf8))
        try h.close()
        await model.tick()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.session?.working?.count, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: probe))
    }

    func testAnUnreadableSetOffersOnlyClose() async throws {
        let bad = scratch + "/Bad Project/Bad.als"
        try FileManager.default.createDirectory(atPath: (bad as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data("not a set".utf8).write(to: URL(fileURLWithPath: bad))
        await model.open(path: bad)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.usable)
        XCTAssertEqual(model.runTitle, .close)
        XCTAssertTrue(model.runEnabled)
        XCTAssertTrue(RescueText.header(model.session!).contains("cannot be read"))
    }

    func testASetWithoutPluginsSaysSo() async throws {
        await model.open(path: try makeSet(devices: []))
        XCTAssertFalse(model.usable)
        XCTAssertTrue(RescueText.header(model.session!).hasPrefix("This set has no third-party plugins"))
    }

    func testTheHeaderExplainsLiveLogFindingsWithOneRefusalLine() async throws {
        let als = try makeSet(devices: threePlugins)
        let prefs = scratch + "/prefs/Live 11.3.35"
        try FileManager.default.createDirectory(atPath: prefs, withIntermediateDirectories: true)
        var lines = ["2026-03-28T10:00:00.000000: info: Loading document \"\(als)\""]
        for i in 1...9 {                                        // the same plugin refused nine times
            lines.append("2026-03-28T10:00:0\(i).000000: info: Audio Unit: Going to restore: Old Comp")
            lines.append("2026-03-28T10:00:0\(i).500000: error: Audio Unit: Restore 1 failed: Old Comp")
        }
        lines.append("2026-03-28T10:00:20.000000: info: VST3: Going to restore: Serum")
        lines.append("2026-03-28T10:30:00.000000: info: Loading document \"/elsewhere.als\"")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: prefs + "/Log.txt"))
        model.logFiles = { LiveLog.files(prefsFolders: [prefs]) }

        await model.open(path: als)
        let s = try XCTUnwrap(model.session)
        let header = RescueText.header(s)
        XCTAssertTrue(header.contains("stops inside VST3 Serum"), header)
        XCTAssertEqual(RescueText.refusedSummary(s.history!.failureGroups), "1 plugin failed to load in that attempt")
        XCTAssertEqual(s.suggest().map(\.name), ["Serum"], "the first probe tries the log's suspect alone")
    }
}
