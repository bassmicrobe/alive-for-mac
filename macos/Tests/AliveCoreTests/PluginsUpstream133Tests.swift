import XCTest
@testable import AliveCore

/// Upstream a6c8dc1 / 9ce4b4b: the plugin list asks the disk about each path once, and loads
/// that run at the same time do not get in each other's way.
final class PluginsUpstream133Tests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var asked: [String] = []
        func add(_ p: String) { lock.lock(); asked.append(p); lock.unlock() }
    }

    /// The scanner log is cumulative and names one file dozens of times.
    func testEachPathIsAskedOnceEvenFromManyThreads() {
        let counter = Counter()
        let cache = PathExistsCache(probe: { counter.add($0); return $0.hasSuffix("0") })
        DispatchQueue.concurrentPerform(iterations: 400) { i in
            XCTAssertEqual(cache.exists("/plugins/p\(i % 20)"), (i % 20) % 10 == 0)
        }
        XCTAssertEqual(counter.asked.count, 20)
        XCTAssertEqual(Set(counter.asked).count, 20)
        XCTAssertFalse(cache.exists(""), "an empty path is not a file and is not asked about")
        XCTAssertEqual(counter.asked.count, 20)
    }

    /// The settings window asks for two answers the moment it opens while a scan may be loading
    /// as well; upstream's loads shared a hash set and spun forever.
    func testLoadsRunningAtTheSameTimeFinishAndAgree() throws {
        let t = makeTemp("machine")
        var log = ""
        for i in 0..<40 {
            let bundle = PluginFixtures.vst3(t, "system/VST3/Plug \(i).vst3")
            log += "2026-01-01T00:00:00.1: info: VST3: found: Plug \(i)\n   vendor: V\n"
                + "   device-class-id: device:vst3:audiofx:\(String(format: "%08x", i))-1111-2222-3333-444444444444?n=P\n"
                + "   version: 1\n   path: \"\(bundle)\"\n\n"
        }
        t.write("home/Library/Preferences/Ableton/Live 11.3.35/PluginScanner.txt", log)
        let locations = PluginLocations(home: t.sub("home"), systemPlugIns: t.sub("system"),
                                        livePreferences: t.sub("home/Library/Preferences/Ableton"))

        let lock = NSLock()
        var answers: [Set<String>] = []
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            let inv = PluginInventory.load(settings: Settings(), locations: locations)
            lock.lock(); answers.append(Set(inv.all.map(\.uid))); lock.unlock()
        }
        XCTAssertEqual(answers.count, 8)
        XCTAssertEqual(answers.first?.count, 40)
        XCTAssertEqual(Set(answers).count, 1, "every load saw the same plugins")
    }
}
