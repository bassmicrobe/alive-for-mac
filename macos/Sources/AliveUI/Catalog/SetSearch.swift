// Mac-only: the search box of the Sets tab, minimal version (wave 1.5). The full filter set
// (plugins, tags, key, tempo…) is `SetFilter` in AliveCore, added by the Sets implementer.
import Foundation
import AliveCore

enum SetSearch {
    /// Every whitespace-separated word of `query` must occur in the set's name or its project's
    /// name; case, diacritics and full/half width are ignored ("ｍｉｘ" finds "Mix", "cafe" finds
    /// "Café"). An empty query matches everything.
    static func matches(_ set: SetEntry, query: String) -> Bool {
        words(in: query).allSatisfy { word in
            contains(set.name, word) || contains(set.projectName, word)
        }
    }

    /// Filters first and only then folds by folder (upstream order): a query for a name that only an
    /// older version of a project carries still finds it.
    static func rows(_ sets: [SetEntry], query: String, groupByFolder: Bool) -> [SetEntry] {
        let matched = words(in: query).isEmpty ? sets : sets.filter { matches($0, query: query) }
        return groupByFolder ? ProjectIndex.collapseByFolder(matched) : matched
    }

    static func words(in query: String) -> [String] {
        query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }

    private static func contains(_ text: String, _ word: String) -> Bool {
        text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
    }
}
