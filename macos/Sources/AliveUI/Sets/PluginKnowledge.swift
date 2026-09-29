// Mac-only: when may the Sets tab call a plugin "missing"?
import AliveCore

enum PluginKnowledge {
    /// An inventory that could not be read (or found nothing) knows nothing: every plugin of every
    /// set would come out "missing", which is noise rather than information (PORTING rule 11).
    static func isKnown(_ inventory: PluginInventory) -> Bool {
        inventory.isAvailable
    }
}
