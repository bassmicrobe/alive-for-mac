import XCTest
@testable import AliveCore

final class SetEntryTests: XCTestCase {
    func testPathDerivedProperties() {
        var s = SetEntry()
        s.path = "/Music/Series 2/somnitelno/X Project/X v1.als"
        XCTAssertEqual(s.id, s.path)
        XCTAssertEqual(s.directory, "/Music/Series 2/somnitelno/X Project")
        XCTAssertEqual(s.projectDir, "/Music/Series 2/somnitelno/X Project")
        XCTAssertEqual(s.place, "somnitelno")
        XCTAssertEqual(s.projectNameFromPath, "X")

        s.path = "/Music/Series 2/somnitelno/X Project/Sub/Deeper/y.als"          // up to three levels above
        XCTAssertEqual(s.projectDir, "/Music/Series 2/somnitelno/X Project")

        s.path = "/Music/Loose/song.als"                                          // not in a "* Project"
        XCTAssertEqual(s.projectDir, "/Music/Loose")
        XCTAssertEqual(s.place, "Music")
        XCTAssertEqual(s.projectNameFromPath, "Loose")

        s.path = "/song.als"
        XCTAssertEqual(s.place, "")
        s.path = "/a/b/c/d/e/f Project/g/h/i/k/j.als"                             // too far above (4 levels max)
        XCTAssertEqual(s.projectDir, "/a/b/c/d/e/f Project/g/h/i/k")
        s.path = "/a/b/c/d/e/f Project/g/h/j.als"                                 // exactly 4 levels: found
        XCTAssertEqual(s.projectDir, "/a/b/c/d/e/f Project")
    }

    func testShortVersionAndHashing() {
        var s = SetEntry()
        s.creator = "Ableton Live 12.4.3"
        XCTAssertEqual(s.shortVersion, "12.4.3")
        s.creator = "Solo"
        XCTAssertEqual(s.shortVersion, "Solo")
        s.creator = ""
        XCTAssertEqual(s.shortVersion, "")
        var a = SetEntry(); a.path = "/p"
        var b = a; b.tempo = 99
        XCTAssertNotEqual(a, b)                                 // views can detect a changed set…
        XCTAssertEqual(Set([a, b]).count, 2)
        XCTAssertEqual(a.hashValue, b.hashValue)                // …while its identity stays the path
    }

    func testPluginStatFormatAndFxType() {
        var st = PluginStat()
        XCTAssertEqual(st.format, "")
        st.uid = "vst3:1"; XCTAssertEqual(st.format, "VST3")
        st.uid = "vst2:1"; XCTAssertEqual(st.format, "VST2")
        st.uid = "au:aufx:a:b"; XCTAssertEqual(st.format, "AU")
        var p = InstalledPlugin(); p.kind = .vst2; p.category = "Fx|Reverb"
        st.installed = p; st.match = .exact
        XCTAssertEqual(st.format, "VST2")
        XCTAssertEqual(st.fxType, "Reverb")
        // Faithful to upstream: a generic tail with nothing before it leaves the raw category.
        for (cat, want) in [("Instrument|Synth", "Synth"), ("Fx", ""), ("Dynamics", "Dynamics"),
                            ("Mastering|Fx", "Mastering"), ("  ", ""), ("Fx|Instrument", "Fx|Instrument")] {
            p.category = cat; st.installed = p
            XCTAssertEqual(st.fxType, want, cat)
        }
        XCTAssertTrue(st.isInstalled)
        st.match = .missing; XCTAssertFalse(st.isInstalled)
        XCTAssertTrue(st.isUnused)
    }
}

final class PluginInventoryTests: XCTestCase {
    private func plugin(_ uid: String, _ name: String, vendor: String = "V", kind: PluginKind = .vst3) -> InstalledPlugin {
        var p = InstalledPlugin(); p.uid = uid; p.name = name; p.vendor = vendor; p.kind = kind
        return p
    }

    func testMatching() {
        var inv = PluginInventory()
        XCTAssertTrue(inv.isEmpty)
        inv.add(plugin("vst3:aaa", "Serum"))
        inv.add(plugin("au:aumu:xfer:Xfer", "Serum 2", kind: .audioUnit))
        XCTAssertFalse(inv.isEmpty)
        XCTAssertEqual(inv.match(uid: "VST3:AAA", name: "x").kind, .exact)
        XCTAssertEqual(inv.match(uid: "vst2:1", name: "Serum_x64").kind, .otherFormat)
        XCTAssertEqual(inv.match(uid: "", name: "Nothing Here").kind, .missing)
        XCTAssertFalse(inv.match(uid: "", name: "Nothing").found)
        XCTAssertTrue(inv.match(uid: "vst3:aaa", name: "").found)
        XCTAssertNil(inv.byUid("")); XCTAssertNil(inv.byName(""))
        XCTAssertEqual(inv.all.count, 2)
        XCTAssertEqual(inv.all[1].format, "AU")
        XCTAssertEqual(inv.all[0].format, "VST3")
        XCTAssertEqual(inv.describe(), "2 plugins")
        inv.error = "broken"
        XCTAssertEqual(inv.describe(), "broken")
    }

    func testNormalize() {
        XCTAssertEqual(PluginInventory.normalize("Serum_x64"), "serum")
        XCTAssertEqual(PluginInventory.normalize("Serum (64 Bit)"), "serum")
        XCTAssertEqual(PluginInventory.normalize("Pro-Q 3"), "proq3")
        XCTAssertEqual(PluginInventory.normalize("VST"), "vst")           // too short to strip
    }
}

final class ProjectIndexTests: XCTestCase {
    private struct Lib {
        let t: TempDir
        let data: String
        let root: String
        let home: String
    }

    private func setXML(tempo: Double, plugin: String = "", sample: String = "") -> String {
        Fx.als(live: Fx.tracks(Fx.track("AudioTrack", extra: plugin + sample)) + Fx.main(tempo: tempo) + Fx.scale(root: 7, name: 0))
    }

    /// Alpha Project: v1, v2, final (+ Backup copy, render, sample); Beta Project: one set with a missing sample.
    private func makeLibrary() -> Lib {
        let t = makeTemp("lib")
        let root = t.mkdir("music")
        let home = t.mkdir("home")
        let kick = t.write("music/Alpha Project/Samples/Imported/kick.wav", String(repeating: "k", count: 100))
        let sample = Fx.fileRef(rel: "Samples/Imported/kick.wav", abs: kick, type: 3, size: 100)
        let plugin = Fx.vst3(name: "Serum", fields: [1, 2, 3, 4], browser: "query:Plugins#VST3:Xfer:Serum")
        t.als("music/Alpha Project/alpha v1.als", setXML(tempo: 120, plugin: plugin), modified: Date(timeIntervalSince1970: 1_700_000_000))
        t.als("music/Alpha Project/alpha v2.als", setXML(tempo: 121, plugin: plugin), modified: Date(timeIntervalSince1970: 1_700_100_000))
        t.als("music/Alpha Project/alpha final.als", setXML(tempo: 122, plugin: plugin, sample: sample),
              modified: Date(timeIntervalSince1970: 1_700_200_000))
        t.als("music/Alpha Project/Backup/alpha [2026-05-22 012035].als", setXML(tempo: 100))
        t.write("music/Alpha Project/render/mix.wav")
        let ghost = Fx.fileRef(rel: "Samples/gone.wav", abs: "/nowhere/gone.wav", type: 3)
        t.als("music/Beta Project/beta.als", setXML(tempo: 90, sample: ghost), modified: Date(timeIntervalSince1970: 1_600_000_000))
        return Lib(t: t, data: t.mkdir("data"), root: root, home: home)
    }

    private func index(_ l: Lib) -> ProjectIndex {
        ProjectIndex(dir: l.data, home: l.home, applicationsDirs: [], settings: Settings())
    }

    func testScanGroupsVersionsAndFillsEntries() throws {
        let l = makeLibrary()
        let idx = index(l)
        let progressCalls = Counter()
        let stats = idx.scan(roots: [l.root], progress: { _, _, _ in progressCalls.bump() })
        XCTAssertEqual(stats.total, 4)                         // Backup copy not in the catalog
        XCTAssertEqual(stats.parsed, 4)
        XCTAssertEqual(stats.reused, 0)
        XCTAssertGreaterThan(progressCalls.value, 0)

        let sets = idx.sets
        XCTAssertEqual(sets.count, 4)
        let final = try XCTUnwrap(sets.first { $0.name == "alpha final" })
        XCTAssertEqual(final.tempo, 122)
        XCTAssertEqual(final.key, "G Major")
        XCTAssertEqual(final.tracks, 1)
        XCTAssertEqual(final.creator, "Ableton Live 12.3.5")
        XCTAssertEqual(final.projectName, "Alpha")
        XCTAssertEqual(final.plugins, ["Serum"])
        XCTAssertEqual(final.pluginVendors, ["Xfer"])
        XCTAssertEqual(final.pluginVendorConfident, [true])
        XCTAssertEqual(final.pluginUids, ["vst3:00000001-0000-0002-0000-000300000004"])
        XCTAssertEqual(final.totalRefs, 1)
        XCTAssertEqual(final.missingFiles, 0)
        XCTAssertEqual(final.samples.count, 1)
        XCTAssertEqual(final.sampleSizes, [100])
        XCTAssertTrue(final.hasRenders)
        XCTAssertEqual(final.renderNames, ["mix"])
        XCTAssertEqual(final.projectFiles, 6)                  // 3 sets + backup + sample + render
        XCTAssertGreaterThan(final.projectSize, 100)
        XCTAssertFalse(final.isBackup)
        XCTAssertEqual(final.size, Int64(try Data(contentsOf: URL(fileURLWithPath: final.path)).count))

        let beta = try XCTUnwrap(sets.first { $0.name == "beta" })
        XCTAssertEqual(beta.missingFiles, 1)
        XCTAssertFalse(beta.hasRenders)

        // Grouping: newest of a folder on top, the rest counted under it.
        let rows = ProjectIndex.collapseByFolder(sets)
        XCTAssertEqual(rows.count, 2)
        let alphaRow = try XCTUnwrap(rows.first { $0.projectName == "Alpha" })
        XCTAssertEqual(alphaRow.name, "alpha final")
        XCTAssertEqual(alphaRow.collapsedCount, 2)
        XCTAssertEqual(idx.inSameFolder(final).map(\.name), ["alpha final", "alpha v2", "alpha v1"])
        XCTAssertEqual(ProjectIndex.collapseByFolder(sets.reversed()).first { $0.projectName == "Alpha" }?.name, "alpha final")
        XCTAssertEqual(idx.env.userLibrary, l.home + "/Music/Ableton/User Library")

        // Activity: 2 backup-less loose sets + the copy from Backup (alpha has a copy → its .als times are skipped).
        XCTAssertGreaterThanOrEqual(idx.history.total, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: l.data + "/activity.cache"))
    }

    func testCacheWrittenReloadedAndUnchangedFilesNotReparsed() throws {
        let l = makeLibrary()
        let first = index(l)
        first.scan(roots: [l.root])
        XCTAssertTrue(FileManager.default.fileExists(atPath: l.data + "/index.cache"))

        // Instant load in a new process-like instance.
        let second = index(l)
        XCTAssertTrue(second.loadFromCache())
        XCTAssertEqual(second.sets.map(\.path).sorted(), first.sets.map(\.path).sorted())
        let a = try XCTUnwrap(first.sets.first { $0.name == "alpha final" })
        let b = try XCTUnwrap(second.sets.first { $0.name == "alpha final" })
        XCTAssertEqual(a.tempo, b.tempo); XCTAssertEqual(a.samples, b.samples)
        XCTAssertEqual(a.pluginUids, b.pluginUids); XCTAssertEqual(a.modified.timeIntervalSince1970, b.modified.timeIntervalSince1970, accuracy: 1e-6)

        let stats = second.scan(roots: [l.root])
        XCTAssertEqual(stats.parsed, 0, "unchanged files must come from the cache")
        XCTAssertEqual(stats.reused, 4)

        // Touch one file: exactly that one is re-parsed.
        l.t.als("music/Beta Project/beta.als", setXML(tempo: 95), modified: Date())
        let third = second.scan(roots: [l.root])
        XCTAssertEqual(third.parsed, 1)
        XCTAssertEqual(third.reused, 3)
        XCTAssertEqual(second.sets.first { $0.name == "beta" }?.tempo, 95)

        // A new file appears, an old one is gone.
        l.t.als("music/Gamma Project/gamma.als", setXML(tempo: 100))
        try FileManager.default.removeItem(atPath: l.t.sub("music/Alpha Project/alpha v1.als"))
        let fourth = second.scan(roots: [l.root])
        XCTAssertEqual(fourth.parsed, 1)
        XCTAssertEqual(second.sets.count, 4)
        XCTAssertEqual(second.lastScanStats, fourth)
    }

    func testDisabledAndNestedRootsAndSettingsOverload() {
        let l = makeLibrary()
        let idx = index(l)
        XCTAssertEqual(idx.scan(roots: [l.root, l.root + "/Alpha Project"]).total, 4)      // nested root: no doubles
        XCTAssertEqual(idx.scan(roots: [l.root], disabledRoots: [l.root.uppercased()]).total, 0)
        var s = Settings(); s.roots = [l.root, l.t.sub("nowhere")]; s.disabledRoots = [l.t.sub("nowhere")]
        XCTAssertEqual(idx.scan(settings: s).total, 4)
        XCTAssertEqual(idx.settings.roots.count, 2)
    }

    func testBrokenSetKeepsARowWithError() throws {
        let l = makeLibrary()
        l.t.write("music/Bad Project/bad.als", "this is not xml at all <<<")
        l.t.write("music/Bad Project/zero.als", "")
        let idx = index(l)
        idx.scan(roots: [l.root])
        let bad = try XCTUnwrap(idx.sets.first { $0.name == "bad" })
        XCTAssertFalse(bad.error.isEmpty)
        XCTAssertEqual(idx.sets.count, 6)
        // The error survives the cache.
        let again = index(l)
        again.loadFromCache()
        XCTAssertFalse(try XCTUnwrap(again.sets.first { $0.name == "bad" }).error.isEmpty)
    }

    func testCancelledScanPublishesNothing() {
        let l = makeLibrary()
        let idx = index(l)
        idx.scan(roots: [l.root])
        let before = idx.sets
        let stats = idx.scan(roots: [l.root], isCancelled: { true })
        XCTAssertTrue(stats.cancelled)
        XCTAssertEqual(idx.sets, before)
    }

    func testAsyncScan() async {
        let l = makeLibrary()
        let idx = index(l)
        let stats = await idx.scanAsync(roots: [l.root])
        XCTAssertEqual(stats.total, 4)
        XCTAssertEqual(idx.sets.count, 4)
    }

    func testCorruptCacheReadsAsEmpty() {
        let l = makeLibrary()
        l.t.write("data/index.cache", "garbage")
        XCTAssertFalse(index(l).loadFromCache())
        var w = DotNetWriter(); w.int32(3); w.int32(0)
        try? w.data.write(to: URL(fileURLWithPath: l.data + "/index.cache"))
        XCTAssertFalse(index(l).loadFromCache())
    }

    func testPluginHealthUsageAndMissingPluginsAgainstInventory() throws {
        let l = makeLibrary()
        var inv = PluginInventory()
        var serum = InstalledPlugin(); serum.uid = "vst3:00000001-0000-0002-0000-000300000004"; serum.name = "Serum"
        serum.vendor = "Xfer Records"; serum.kind = .vst3
        var idle = InstalledPlugin(); idle.uid = "vst3:idle"; idle.name = "Idle One"; idle.vendor = "Someone"; idle.fileMissing = true
        inv.add(serum); inv.add(idle)

        let installed = inv
        let idx = index(l)
        idx.inventoryLoader = { _ in installed }
        idx.scan(roots: [l.root])
        XCTAssertEqual(idx.inventory.all.count, 2)
        let alpha = try XCTUnwrap(idx.sets.first { $0.name == "alpha v1" })
        XCTAssertEqual(alpha.pluginUids, [serum.uid])
        XCTAssertEqual(alpha.missingPlugins, 0)

        let usage = idx.pluginUsage()
        XCTAssertEqual(usage.map(\.name), ["Serum", "Idle One"])
        XCTAssertEqual(usage[0].sets, 3 + 0)
        XCTAssertEqual(usage[0].vendor, "Xfer Records")      // the inventory's vendor wins
        XCTAssertEqual(usage[0].match, .exact)
        XCTAssertTrue(usage[1].isUnused)
        let h = idx.health(usage)
        XCTAssertEqual(h.used, 1); XCTAssertEqual(h.installed, 1); XCTAssertEqual(h.missing, 0)
        XCTAssertEqual(h.installedTotal, 2); XCTAssertEqual(h.installedUnused, 1); XCTAssertEqual(h.filesGone, 1)
        XCTAssertTrue(idx.pluginUsage().map(\.name) == usage.map(\.name))          // cached snapshot

        // Uninstall Serum: sets now miss one plugin, the summary follows.
        // (An *empty* inventory would mean "unknown", not "missing": see PluginMissingStateTests.)
        var other = InstalledPlugin(); other.uid = "vst3:other"; other.name = "Other"
        var remaining = PluginInventory(); remaining.add(other)
        let stillThere = remaining
        idx.inventoryLoader = { _ in stillThere }
        idx.refreshInstalled()
        XCTAssertEqual(idx.sets.first { $0.name == "alpha v1" }?.missingPlugins, 1)
        XCTAssertEqual(idx.pluginUsage().first?.match, .missing)
        XCTAssertEqual(idx.health(idx.pluginUsage()).missing, 1)
    }

    func testAcceptVendorOnlyForConfirmedNames() {
        let l = makeLibrary()
        let idx = index(l)
        idx.scan(roots: [l.root])                              // Serum/Xfer is confident (VST3)
        XCTAssertTrue(idx.knownVendors.contains("xfer"))
        XCTAssertEqual(idx.acceptVendor("Xfer", confident: false), "Xfer")
        XCTAssertEqual(idx.acceptVendor("Eff", confident: false), "")
        XCTAssertEqual(idx.acceptVendor("Eff", confident: true), "Eff")
        XCTAssertEqual(idx.acceptVendor("", confident: true), "")
    }

    func testPluginsDeduplicatedPerSetPreferringConfidentVendor() {
        var e = SetEntry()
        var weak = PluginRef(kind: .vst3); weak.name = "Pro-Q"; weak.manufacturer = "Eff"
        var strong = PluginRef(kind: .vst3); strong.name = "pro-q"; strong.manufacturer = "FabFilter"; strong.vendorConfident = true; strong.uid = "vst3:x"
        var other = PluginRef(kind: .vst2); other.name = "Alpha"
        SetBuilder.applyPlugins([weak, strong, other, PluginRef(kind: .vst2)], to: &e)
        XCTAssertEqual(e.plugins, ["Alpha", "pro-q"])
        XCTAssertEqual(e.pluginVendors, ["", "FabFilter"])
        XCTAssertEqual(e.pluginUids, ["", "vst3:x"])
    }
}
