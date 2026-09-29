// Mac-only: cell text and labels of the Plugins tab (upstream: the Text delegates of
// PluginCatalog in MainForm.cs). Pure functions over core types, so they are unit-testable.
import Foundation
import AliveCore

enum PluginsFormat {
    /// "—" for a plugin used in no set.
    static func sets(_ n: Int) -> String { n > 0 ? String(n) : "—" }

    static func setsPhrase(_ n: Int) -> String {
        (n == 1 ? PluginsStrings.setsOne : PluginsStrings.setsMany).f(n)
    }

    /// The date the newest set using the plugin was saved; "—" when it is used nowhere.
    static func lastUsed(_ date: Date?, locale: Locale = Localizer.shared.locale) -> String {
        guard let date, date > .distantPast else { return "—" }
        return date.formatted(.dateTime.year().month().day().locale(locale))
    }

    static func role(_ role: PluginRole) -> String {
        switch role {
        case .instrument: return PluginsStrings.roleInstrument.s
        case .effect: return PluginsStrings.roleEffect.s
        case .unknown: return ""
        }
    }

    /// The type column: the category from the bundle ("EQ", "Synth"), else instrument / effect.
    static func type(_ row: PluginRow) -> String {
        row.fxType.isEmpty ? role(row.role) : row.fxType
    }

    static func status(_ status: PluginStatus) -> String {
        switch status {
        case .installed: return PluginsStrings.statusInstalled.s
        case .otherFormat: return PluginsStrings.statusOtherFormat.s
        case .missing: return PluginsStrings.statusNotInstalled.s
        case .unknown: return PluginsStrings.statusUnknown.s
        }
    }

    static func column(_ column: PluginColumn) -> String {
        switch column {
        case .name: return PluginsStrings.colPlugin.s
        case .vendor: return PluginsStrings.colDeveloper.s
        case .fxType: return PluginsStrings.colType.s
        case .format: return PluginsStrings.colFormat.s
        case .sets: return PluginsStrings.colSets.s
        case .lastUsed: return PluginsStrings.colLastUsed.s
        case .version: return PluginsStrings.colVersion.s
        case .file: return PluginsStrings.colFile.s
        case .status: return PluginsStrings.colStatus.s
        }
    }

    static func card(_ card: PluginCard) -> String {
        switch card {
        case .used: return PluginsStrings.cardUsed.s
        case .installed: return PluginsStrings.cardInstalled.s
        case .missing: return PluginsStrings.cardMissing.s
        case .unused: return PluginsStrings.cardUnused.s
        }
    }

    /// The filter's stand-in names in the UI language.
    static func vendorLabel(_ vendor: String) -> String {
        vendor == PluginFilter.unknownVendor ? PluginsStrings.filterUnknown.s : vendor
    }

    static func categoryLabel(_ category: String) -> String {
        category == PluginFilter.otherCategory ? PluginsStrings.filterOther.s : category
    }

    static func formatLabel(_ format: String) -> String {
        format == "Other" ? PluginsStrings.filterOther.s : format
    }

    /// The number on a summary card. The "installed" card counts the rows the list shows (the
    /// inventory holds one entry per format and path, the list one row per plugin), so what the
    /// card says and what a click on it leaves in the list are the same number.
    static func cardValue(_ card: PluginCard, health: PluginHealth, rows: [PluginRow]) -> Int {
        card == .installed ? rows.filter { card.passes($0.stat) }.count : card.value(health)
    }

    static func missingSummary(_ count: Int) -> String {
        count == 1 ? PluginsStrings.missingSummaryOne.s : PluginsStrings.missingSummaryMany.f(count)
    }

    /// The category as the bundle spells it, made readable: "Fx|EQ" -> "Fx · EQ".
    static func category(_ raw: String) -> String {
        raw.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " · ")
    }
}
