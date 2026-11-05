import XCTest
import AliveCore
@testable import AliveUI

/// The "copy list" link at the Plugins heading of the detail panel (0bb4915, 9f47c04).
final class SetsPluginListUpstream133Tests: XCTestCase {
    private func installed(_ name: String, uid: String, kind: PluginKind, vendor: String, version: String) -> InstalledPlugin {
        var p = InstalledPlugin()
        p.name = name; p.uid = uid; p.kind = kind; p.vendor = vendor; p.version = version
        return p
    }

    private func set(_ plugins: [(name: String, uid: String, vendor: String)]) -> SetEntry {
        var s = SetEntry()
        s.name = "Night Drive"
        s.plugins = plugins.map(\.name)
        s.pluginUids = plugins.map(\.uid)
        s.pluginVendors = plugins.map(\.vendor)
        return s
    }

    func testListNamesTheSetThenInstalledAndMissingWithTabSeparatedColumns() {
        var inventory = PluginInventory()
        inventory.add(installed("Pro-Q 3", uid: "vst3:aaaa", kind: .vst3, vendor: "FabFilter", version: "3.24"))
        let s = set([("Pro-Q 3", "vst3:aaaa", ""),
                     ("Old Synth", "vst2:1234", "Acme"),
                     ("Chorus AU", "au:aufx:chor:acme", "")])

        let text = PluginListText.make(for: s, inventory: inventory, installedHeading: "Installed:", missingHeading: "Missing:")

        XCTAssertEqual(text, [
            "Night Drive",
            "Installed:",
            "Pro-Q 3\t3.24\tVST3\tFabFilter",
            "Missing:",
            "Old Synth\t\tVST2\tAcme",
            "Chorus AU\t\tAU\t",
        ].joined(separator: "\n"))
    }

    func testPluginsOfAnUnreadableInventoryAreNotCalledInstalledOrMissing() {
        let s = set([("Pro-Q 3", "vst3:aaaa", "FabFilter")])
        let text = PluginListText.make(for: s, inventory: PluginInventory(), installedHeading: "Installed:", missingHeading: "Missing:")
        XCTAssertEqual(text, "Night Drive\nPro-Q 3\t\tVST3\tFabFilter")
    }
}
