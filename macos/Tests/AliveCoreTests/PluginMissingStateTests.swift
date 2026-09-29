import XCTest
@testable import AliveCore

/// Missing plugins are a state, not an error: an unreadable inventory reports nothing missing,
/// real misses are counted once, and the log gets one summary line per refresh.
final class PluginMissingStateTests: XCTestCase {
    private func sets() -> [SetEntry] {
        (1...4).map { i in
            PluginTableTests.set("s\(i)", plugins: [("Alpha", "vst3:a"), ("Beta", "vst3:b"), ("Gamma", "au:aumu:gamm:vend")],
                                 modified: TimeInterval(i))
        }
    }

    func testEmptyInventoryMeansUnknownNotMissing() {
        let idx = PluginTableTests.index(sets: sets(), installed: nil)
        XCTAssertFalse(idx.inventory.isAvailable)
        XCTAssertTrue(idx.sets.allSatisfy { $0.missingPlugins == 0 })
        let usage = idx.pluginUsage()
        XCTAssertEqual(usage.count, 3)
        XCTAssertTrue(usage.allSatisfy { $0.match == .unknown })
        XCTAssertTrue(usage.allSatisfy { $0.status == .unknown })
        let h = idx.health(usage)
        XCTAssertEqual(h.used, 3)
        XCTAssertEqual(h.missing, 0)
        XCTAssertEqual(h.installed, 0)
        XCTAssertEqual(h.otherFormat, 0)
        // No card and no filter can select a "missing" plugin out of an unknown state.
        XCTAssertTrue(usage.allSatisfy { !PluginCard.missing.passes($0) })
        var f = PluginFilter(); f.statusMissing = true
        XCTAssertTrue(usage.allSatisfy { !f.matches($0) })
    }

    func testUnavailableInventoryFromAFailedLoadBehavesTheSame() {
        // What `load` returns when nothing could be read: empty, with the reason in `error`.
        var inv = PluginInventory()
        inv.error = "No plugins found in the plug-in folders"
        let idx = ProjectIndex(dir: NSTemporaryDirectory() + "pms-" + UUID().uuidString, settings: Settings())
        idx.lock.lock(); idx._sets = sets(); idx.lock.unlock()
        let frozen = inv
        idx.inventoryLoader = { _ in frozen }
        idx.refreshInstalled()
        XCTAssertTrue(idx.sets.allSatisfy { $0.missingPlugins == 0 })
        XCTAssertEqual(idx.health(idx.pluginUsage()).missing, 0)
    }

    func testRealMissesAreCountedAsOneAggregate() {
        // Only Alpha is installed: Beta and Gamma are missing from all four sets.
        let idx = PluginTableTests.index(sets: sets(), installed: [PluginTableTests.installed("vst3:a", "Alpha")])
        XCTAssertTrue(idx.inventory.isAvailable)
        XCTAssertTrue(idx.sets.allSatisfy { $0.missingPlugins == 2 })
        let usage = idx.pluginUsage()
        XCTAssertEqual(usage.filter { $0.match == .missing }.map(\.name).sorted(), ["Beta", "Gamma"])
        let h = idx.health(usage)
        XCTAssertEqual(h.missing, 2)                                   // distinct plugins, not 8 set/plugin pairs
        XCTAssertEqual(h.installed, 1)
        XCTAssertEqual(h.used, 3)
    }

    func testPluginsUsedInSetsWithoutAnyPluginsAreNotCounted() {
        var quiet = SetEntry(); quiet.path = "/q.als"; quiet.name = "q"
        let idx = PluginTableTests.index(sets: [quiet], installed: [PluginTableTests.installed("vst3:a", "Alpha")])
        XCTAssertEqual(idx.sets.first?.missingPlugins, 0)
        XCTAssertEqual(idx.health(idx.pluginUsage()).used, 0)
    }

    func testOneSummaryLinePerRefreshAndNeverOnePerPlugin() throws {
        let dir = NSTemporaryDirectory() + "pms-log-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Diag.start(dir: dir)
        defer { Diag.stop(); try? FileManager.default.removeItem(atPath: dir) }

        let missing = PluginTableTests.index(sets: sets(), installed: [PluginTableTests.installed("vst3:a", "Alpha")])
        _ = missing.pluginUsage()
        let unavailable = PluginTableTests.index(sets: sets(), installed: nil)
        _ = unavailable.pluginUsage()

        let log = try String(contentsOfFile: Diag.defaultLogPath(dir: dir), encoding: .utf8)
        let pluginLines = log.components(separatedBy: "\n").filter { $0.contains("plugins:") }
        XCTAssertEqual(pluginLines.count, 2, "one line per refresh: \(pluginLines)")
        XCTAssertTrue(pluginLines[0].contains("2 used plugins not installed, in 4 sets"), pluginLines[0])
        XCTAssertTrue(pluginLines[1].contains("unavailable"), pluginLines[1])
        XCTAssertFalse(log.contains("Beta"), "plugin names must not be logged one by one")
    }

    func testTheStatusOfAnUnavailableInventoryStaysUnknownAcrossReload() {
        let idx = PluginTableTests.index(sets: sets(), installed: nil)
        idx.refreshInstalled()
        idx.refreshInstalled()
        XCTAssertTrue(idx.pluginUsage().allSatisfy { $0.match == .unknown })
    }
}
