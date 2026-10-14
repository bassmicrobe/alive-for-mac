// Mac-only: what Alive tells Spotlight about one set, as plain values (no CoreSpotlight types),
// so the diff and the text are testable without touching the system index.
import Foundation
import AliveCore

struct SpotlightDocument: Equatable, Sendable {
    /// The file path of the .als; also the identifier Spotlight hands back on a click.
    var id: String
    var title: String
    var displayName: String
    var contentDescription: String
    var keywords: [String]
    var modified: Date
    var created: Date

    /// Changes whenever anything Spotlight shows changes (stable across launches: FNV-1a).
    var signature: String {
        let parts = [id, title, displayName, contentDescription, keywords.joined(separator: "\u{1}"),
                     String(modified.timeIntervalSince1970), String(created.timeIntervalSince1970)]
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in parts.joined(separator: "\u{0}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    /// nil for sets that do not belong in the index (Live's Backup copies).
    static func make(for set: SetEntry, tags: [String], description: String) -> SpotlightDocument? {
        guard !set.isBackup, !set.path.isEmpty else { return nil }
        let name = set.name.isEmpty
            ? ((set.path as NSString).lastPathComponent as NSString).deletingPathExtension : set.name
        var keywords: [String] = []
        func add(_ values: [String]) {
            for v in values where !v.isEmpty && !keywords.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) {
                keywords.append(v)
            }
        }
        add(set.plugins); add(set.pluginVendors); add(tags); add([set.projectName, set.key])
        return SpotlightDocument(id: set.path, title: name, displayName: name, contentDescription: description,
                                 keywords: keywords, modified: set.modified, created: set.created)
    }

    /// "140 BPM · C Major · 12 トラック · Live 11.3" in the given language (captured on the main actor
    /// by the caller, never read from `Localizer` here); unknown parts are left out.
    static func describe(_ set: SetEntry, lang: Lang, locale: Locale) -> String {
        var parts: [String] = []
        if set.tempo > 0 {
            let bpm = set.tempo == set.tempo.rounded() ? String(Int(set.tempo)) : String(format: "%.1f", set.tempo)
            parts.append("\(bpm) BPM")
        }
        if !set.key.isEmpty { parts.append(set.key) }
        if set.tracks > 0 { parts.append(IntegrationStrings.itemTracks.f(lang: lang, locale: locale, set.tracks)) }
        if !set.creator.isEmpty { parts.append(IntegrationStrings.itemLive.f(lang: lang, locale: locale, set.shortVersion)) }
        return parts.joined(separator: " · ")
    }
}
