// Port of DetailPanel.CopyPluginsToClipboard (src/DetailPanel.cs, 0bb4915): the text behind the
// "copy list" link at the Plugins heading. Pure, so the layout is tested without a pasteboard.
import Foundation
import AliveCore

enum PluginListText {
    /// The set's name, then an "Installed" and a "Missing" section, one tab-separated line per
    /// plugin: name, version, format, developer. A section with no plugins is left out.
    ///
    /// Mac addition: while the installed plugins could not be read nothing is known, so such
    /// plugins go under the name without a heading rather than into either section (PORTING rule
    /// 11: unknown is not missing).
    static func make(for set: SetEntry, inventory: PluginInventory,
                     installedHeading: String = SetsStrings.pluginListInstalled.s,
                     missingHeading: String = SetsStrings.pluginListMissing.s) -> String {
        var installed: [String] = [], missing: [String] = [], unknown: [String] = []
        for (index, name) in set.plugins.enumerated() {
            let uid = index < set.pluginUids.count ? set.pluginUids[index] : ""
            let match = inventory.match(uid: uid, name: name)
            let line = [name, match.plugin?.version ?? "", format(of: match.plugin, uid: uid),
                        developer(of: match.plugin, in: set, at: index)].joined(separator: "\t")
            switch match.kind {
            case .exact, .otherFormat: installed.append(line)
            case .missing: missing.append(line)
            case .unknown: unknown.append(line)
            }
        }
        var lines = [set.name] + unknown
        if !installed.isEmpty { lines += [installedHeading] + installed }
        if !missing.isEmpty { lines += [missingHeading] + missing }
        return lines.joined(separator: "\n")
    }

    /// The installed plugin's format; for one that is not installed, the format its identifier names.
    private static func format(of plugin: InstalledPlugin?, uid: String) -> String {
        if let plugin { return plugin.format }
        // "vst3:…", "vst2:…", "au:…", or "file:<format>:<name>" for a bundle known by name.
        let parts = uid.lowercased().split(separator: ":", omittingEmptySubsequences: false)
        let tag = parts.first == "file" && parts.count > 1 ? parts[1] : (parts.first ?? "")
        switch tag {
        case "vst3": return "VST3"
        case "vst2": return "VST2"
        case "au": return "AU"
        default: return ""
        }
    }

    private static func developer(of plugin: InstalledPlugin?, in set: SetEntry, at index: Int) -> String {
        if let vendor = plugin?.vendor, !vendor.isEmpty { return vendor }
        return index < set.pluginVendors.count ? set.pluginVendors[index] : ""
    }
}
