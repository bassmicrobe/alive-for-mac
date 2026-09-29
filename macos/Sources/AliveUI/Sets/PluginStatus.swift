// Mac-only: when may the Sets tab call a plugin "missing"?
import AliveCore

enum PluginStatus {
    /// An inventory that could not be read (or is empty) knows nothing: every plugin of every set
    /// would come out "missing", which is noise rather than information. The Plugins implementer
    /// is adding an availability flag to `PluginInventory`; until it lands an empty list means
    /// "unknown".
    static func isKnown(_ inventory: PluginInventory) -> Bool {
        !inventory.all.isEmpty
    }
}
