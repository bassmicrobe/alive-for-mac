import XCTest
@testable import AliveCore

/// Usage counting on synthetic sets, the table rows, sorting, the summary cards.
final class PluginTableTests: XCTestCase {
    static func set(_ name: String, plugins: [(String, String)], modified: TimeInterval) -> SetEntry {
        var e = SetEntry()
        e.path = "/music/\(name).als"
        e.name = name
        e.modified = Date(timeIntervalSince1970: modified)
        e.plugins = plugins.map(\.0)
        e.pluginUids = plugins.map(\.1)
        e.pluginVendors = plugins.map { _ in "" }
        e.pluginVendorConfident = plugins.map { _ in false }
        return e
    }

    /// An index holding `sets` and an inventory of `installed` (no disk involved).
    static func index(sets: [SetEntry], installed: [InstalledPlugin]?) -> ProjectIndex {
        let idx = ProjectIndex(dir: NSTemporaryDirectory() + "plugin-table-" + UUID().uuidString, settings: Settings())
        idx.lock.lock(); idx._sets = sets; idx._generation += 1; idx.lock.unlock()
        var inv = PluginInventory()
        for p in installed ?? [] { inv.add(p) }
        let frozen = inv
        idx.inventoryLoader = { _ in frozen }
        idx.refreshInstalled()
        return idx
    }

    static func installed(_ uid: String, _ name: String, vendor: String = "", kind: PluginKind = .vst3, category: String = "") -> InstalledPlugin {
        var p = InstalledPlugin()
        p.uid = uid; p.name = name; p.vendor = vendor; p.kind = kind; p.category = category; p.path = "/plugins/\(name)"
        return p
    }

    private var fixture: (ProjectIndex, PluginTable) {
        let sets = [
            Self.set("a", plugins: [("Serum", "vst3:s"), ("Pro-Q", "vst3:q")], modified: 300),
            Self.set("b", plugins: [("serum", "vst3:s"), ("Ghost", "vst2:9")], modified: 100),
            Self.set("c", plugins: [("Pro-Q", "vst3:q")], modified: 200),
        ]
        let idx = Self.index(sets: sets, installed: [
            Self.installed("vst3:s", "Serum", vendor: "Xfer", category: "Instrument|Synth"),
            Self.installed("vst3:q", "Pro-Q", vendor: "FabFilter", category: "Fx|EQ"),
            Self.installed("vst3:idle", "Idle One", vendor: "Nobody", category: "Fx|Reverb"),
        ])
        return (idx, PluginTable(usage: idx.pluginUsage(), sets: idx.sets))
    }

    func testUsageIsCountedPerSetCaseInsensitivelyAndUnusedAreListed() {
        let (_, table) = fixture
        let byName = Dictionary(uniqueKeysWithValues: table.rows.map { ($0.name.lowercased(), $0) })
        XCTAssertEqual(table.rows.count, 4)                        // Serum, Pro-Q, Ghost, Idle One
        XCTAssertEqual(byName["serum"]?.sets, 2)
        XCTAssertEqual(byName["pro-q"]?.sets, 2)
        XCTAssertEqual(byName["ghost"]?.status, .missing)
        XCTAssertEqual(byName["idle one"]?.sets, 0)
        XCTAssertEqual(byName["idle one"]?.status, .installed)
    }

    func testSetsUsingAPluginAreNewestFirstAndLastUsedIsTheNewest() {
        let (_, table) = fixture
        XCTAssertEqual(table.sets(using: "Serum").map(\.name), ["a", "b"])
        XCTAssertEqual(table.sets(using: "SERUM").map(\.name), ["a", "b"])       // by name, ignoring case
        XCTAssertEqual(table.sets(using: "Pro-Q").map(\.name), ["a", "c"])
        XCTAssertEqual(table.sets(using: "nothing"), [])
        XCTAssertEqual(table.row(named: "serum")?.lastUsed, Date(timeIntervalSince1970: 300))
        XCTAssertNil(table.row(named: "Idle One")?.lastUsed)
        XCTAssertNil(table.row(named: "zzz"))
    }

    func testTheSameSetIsNotCountedTwiceForOnePlugin() {
        let e = Self.set("twice", plugins: [("Serum", "vst3:s"), ("Serum", "vst3:s")], modified: 1)
        let table = PluginTable(usage: [], sets: [e])
        XCTAssertEqual(table.sets(using: "Serum").count, 1)
    }

    func testRolesAndStatuses() {
        let (_, table) = fixture
        XCTAssertEqual(table.row(named: "Serum")?.role, .instrument)
        XCTAssertEqual(table.row(named: "Pro-Q")?.role, .effect)
        XCTAssertEqual(table.row(named: "Ghost")?.role, .unknown)
        var st = PluginStat(); st.match = .exact
        var p = InstalledPlugin(); p.fileMissing = true
        st.installed = p
        XCTAssertEqual(st.status, .missing)                        // Live remembers it, the file is gone
        for (cat, want) in [("Instrument", PluginRole.instrument), ("Fx", .effect), ("Fx|Instrument", .effect),
                            ("Instrument|Synth", .instrument), ("MIDI Effect", .effect), ("Generator", .instrument), ("", .unknown)] {
            var s = PluginStat(); var q = InstalledPlugin(); q.category = cat; s.installed = q; s.match = .exact
            XCTAssertEqual(s.role, want, cat)
        }
    }

    // MARK: sorting

    private func order(_ column: PluginColumn, _ order: SortOrder = .forward) -> [String] {
        fixture.1.rows.sorted(using: PluginSort(column, order: order)).map(\.name)
    }

    func testSortByNameVendorSetsAndStatus() {
        XCTAssertEqual(order(.name), ["Ghost", "Idle One", "Pro-Q", "Serum"])
        XCTAssertEqual(order(.name, .reverse), ["Serum", "Pro-Q", "Idle One", "Ghost"])
        // The developer column puts the nameless last in either direction.
        XCTAssertEqual(order(.vendor), ["Pro-Q", "Idle One", "Serum", "Ghost"])
        XCTAssertEqual(order(.vendor, .reverse), ["Serum", "Idle One", "Pro-Q", "Ghost"])
        XCTAssertEqual(order(.sets, .reverse).first == "Pro-Q" || order(.sets, .reverse).first == "Serum", true)
        XCTAssertEqual(order(.sets).first, "Idle One")
        XCTAssertEqual(order(.status).last, "Ghost")
    }

    func testSortByLastUsedPutsNeverUsedLast() {
        XCTAssertEqual(order(.lastUsed).last, "Idle One")
        XCTAssertEqual(order(.lastUsed, .reverse).last, "Idle One")
        XCTAssertEqual(order(.lastUsed, .reverse).first, "Serum")           // saved at 300, ties by name
    }

    func testVersionsAreComparedAsNumbers() {
        XCTAssertEqual(PluginSort.compareVersion("12.4.3", "9.7.2"), .orderedDescending)
        XCTAssertEqual(PluginSort.compareVersion("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(PluginSort.compareVersion("1.10", "1.9"), .orderedDescending)
        XCTAssertEqual(PluginSort.compareVersion("2.0b3", "2.0"), .orderedSame)
        XCTAssertEqual(PluginSort.compareVersion("", "1"), .orderedAscending)
    }

    func testSortByVersionFormatTypeAndFile() {
        var a = PluginStat(); a.name = "A"; var pa = InstalledPlugin(); pa.version = "9.0"; pa.path = "/b"; pa.kind = .vst2; pa.category = "Fx|EQ"
        a.installed = pa; a.match = .exact; a.uid = "vst2:1"
        var b = PluginStat(); b.name = "B"; var pb = InstalledPlugin(); pb.version = "12.0"; pb.path = "/a"; pb.kind = .vst3; pb.category = "Fx|Dynamics"
        b.installed = pb; b.match = .exact; b.uid = "vst3:1"
        let rows = [PluginRow(stat: a, lastUsed: nil), PluginRow(stat: b, lastUsed: nil)]
        func names(_ c: PluginColumn) -> [String] { rows.sorted(using: PluginSort(c)).map(\.name) }
        XCTAssertEqual(names(.version), ["A", "B"])
        XCTAssertEqual(names(.file), ["B", "A"])
        XCTAssertEqual(names(.format), ["A", "B"])          // "VST2" before "VST3"
        XCTAssertEqual(names(.fxType), ["B", "A"])
    }

    // MARK: search and cards

    func testSearchMatchesNameVendorTypeAndFormatByWords() {
        let (_, table) = fixture
        func hits(_ q: String) -> [String] {
            let words = q.components(separatedBy: " ").filter { !$0.isEmpty }
            return table.rows.filter { $0.matches(search: words) }.map(\.name).sorted()
        }
        XCTAssertEqual(hits("serum"), ["Serum"])
        XCTAssertEqual(hits("fabfilter"), ["Pro-Q"])
        XCTAssertEqual(hits("eq"), ["Pro-Q"])
        XCTAssertEqual(hits("vst3 xfer"), ["Serum"])
        XCTAssertEqual(hits(""), ["Ghost", "Idle One", "Pro-Q", "Serum"])
        XCTAssertEqual(hits("nomatch"), [])
    }

    func testSummaryCardsAreFiltersAndTonesFollowUpstream() {
        let (idx, table) = fixture
        let health = idx.health(idx.pluginUsage())
        XCTAssertEqual(PluginCard.used.value(health), 3)
        XCTAssertEqual(PluginCard.installed.value(health), 3)
        XCTAssertEqual(PluginCard.missing.value(health), 1)
        XCTAssertEqual(PluginCard.unused.value(health), 1)
        XCTAssertEqual(PluginCard.missing.tone(health), .bad)
        XCTAssertEqual(PluginCard.installed.tone(health), .good)
        XCTAssertEqual(PluginCard.unused.tone(health), .dim)
        func names(_ c: PluginCard) -> [String] { table.rows.filter { c.passes($0.stat) }.map(\.name).sorted() }
        XCTAssertEqual(names(.used), ["Ghost", "Pro-Q", "Serum"])
        XCTAssertEqual(names(.missing), ["Ghost"])
        XCTAssertEqual(names(.installed), ["Idle One", "Pro-Q", "Serum"])
        XCTAssertEqual(names(.unused), ["Idle One"])
        var none = PluginHealth(); none.missing = 0
        XCTAssertEqual(PluginCard.missing.tone(none), .normal)
    }
}
