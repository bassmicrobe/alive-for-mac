import XCTest
@testable import AliveCore

/// Smoke tests against this machine's real plugins, gated by environment variables and skipped
/// otherwise (they read the real /Library/Audio/Plug-Ins and ~/Library/Preferences/Ableton; they
/// never load a plugin).
///   ALIVE_TEST_PLUGINS=1            inventory counts and timing
///   ALIVE_TEST_AUVAL=<file>         differential against the system's AU list (see the test)
///   ALIVE_TEST_SETS=<projects dir>  how the plugins used in real sets match the inventory
final class PluginRealMachineTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    func testInventoryOfThisMachine() throws {
        guard env["ALIVE_TEST_PLUGINS"] == "1" else { throw XCTSkip("ALIVE_TEST_PLUGINS not set") }
        let started = Date()
        let inv = PluginInventory.load(settings: Settings())
        let seconds = Date().timeIntervalSince(started)
        let byFormat = Dictionary(grouping: inv.all, by: \.format).mapValues(\.count)
        let fileOnly = inv.all.filter(\.isFileIdentified).count
        print("PLUGINS: \(inv.all.count) in \(String(format: "%.2f", seconds))s, by format \(byFormat.sorted { $0.key < $1.key }), "
              + "identified by file only: \(fileOnly), sources: \(inv.sources), version: \(inv.liveVersion)")
        var folderSettings = Settings()
        folderSettings.pluginsFromFolders = true
        let folders = PluginInventory.load(settings: folderSettings)
        print("PLUGINS (folders only): \(folders.all.count); \(folders.sources)")
        XCTAssertGreaterThan(inv.all.count, 0)
        XCTAssertLessThan(seconds, 10)
    }

    /// The system's Audio Unit list as fixed-width lines "type subtype manufacturer" (four
    /// characters each, blanks kept). `auval -a` prints the same list but loads every plugin and
    /// takes minutes with hundreds installed; enumerating `AudioComponentFindNext` gives it at once.
    func testAudioUnitsAgainstSystemList() throws {
        guard let file = env["ALIVE_TEST_AUVAL"], let text = try? String(contentsOfFile: file, encoding: .utf8) else {
            throw XCTSkip("ALIVE_TEST_AUVAL not set")
        }
        let sys = Set(text.components(separatedBy: "\n").filter { $0.count == 14 }.map { line -> String in
            let c = Array(line)
            return (String(c[0..<4]) + ":" + String(c[5..<9]) + ":" + String(c[10..<14])).lowercased()
        })
        let inv = PluginInventory.load(settings: Settings())
        let ours = Set(inv.all.filter { $0.uid.hasPrefix("au:") }.map { String($0.uid.dropFirst(3)).lowercased() })
        let missing = sys.subtracting(ours), extra = ours.subtracting(sys)
        let apple = missing.filter { $0.hasSuffix(":appl") }
        print("AU DIFF: system \(sys.count), ours \(ours.count), only in system \(missing.count) "
              + "(of which Apple's own \(apple.count)), only ours \(extra.count)")
        for m in missing.subtracting(apple).sorted().prefix(30) { print("  only in system: \(m)") }
        for e in extra.sorted().prefix(30) { print("  only ours: \(e)") }
        XCTAssertLessThan(Double(missing.subtracting(apple).count), Double(sys.count) * 0.05)
    }

    func testPluginsUsedInRealSetsMatch() throws {
        guard let root = env["ALIVE_TEST_SETS"], !root.isEmpty else { throw XCTSkip("ALIVE_TEST_SETS not set") }
        // ALIVE_TEST_DATA keeps the catalog cache between runs: the first run scans (slow: it also
        // weighs every project folder), later runs read the cache and only redo the matching.
        let dataPath = env["ALIVE_TEST_DATA"] ?? makeTemp("plugins-real").path
        try FileManager.default.createDirectory(atPath: dataPath, withIntermediateDirectories: true)
        let idx = ProjectIndex(dir: dataPath, settings: Settings())
        if !idx.loadFromCache() { idx.scan(roots: [root]) } else { idx.refreshInstalled() }
        let usage = idx.pluginUsage().filter { !$0.isUnused }
        let counts = Dictionary(grouping: usage, by: { "\($0.match)" }).mapValues(\.count)
        print("USED PLUGINS: \(usage.count) distinct, match \(counts.sorted { $0.key < $1.key }); "
              + "health \(idx.health(idx.pluginUsage()))")
        for st in usage.filter({ $0.match != .exact }).prefix(400) {
            print("  \(st.match) \(st.sets)x \(st.name) [\(st.uid)]"
                  + (st.installed.map { " ~ \($0.name) (\($0.format))" } ?? ""))
        }
        XCTAssertFalse(usage.isEmpty)
    }
}
