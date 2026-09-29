// Port of the column catalogue in src/MainForm.cs (ColDef / Catalog / DefaultSetCols): which
// columns the sets list can show, their default widths and how each one sorts.
import Foundation
import SwiftUI
import AliveCore

/// The ids are upstream's (`ColDef.Id`); they also serve as `customizationID`s in the saved
/// column layout.
enum SetColumnID: String, CaseIterable, Identifiable, Codable, Sendable {
    case set = "Set", place = "Place", modified = "Modified", created = "Created", live = "Live"
    case bpm = "BPM", key = "Key", tracks = "Tracks", pluginCount = "PluginCount", fileCount = "FileCount"
    case pluginsMissed = "Plugins", filesMissed = "Files", tags = "Tags", size = "Size"

    var id: String { rawValue }

    /// Columns shown on first run and after "reset" (upstream `DefaultSetCols`).
    static let defaults: Set<SetColumnID> = [.set, .modified, .bpm, .pluginCount, .fileCount, .tags, .size]

    var isDefault: Bool { Self.defaults.contains(self) }

    /// The name column cannot be hidden.
    var isMandatory: Bool { self == .set }

    var title: SetsStrings {
        switch self {
        case .set: return .colName
        case .place: return .colPlace
        case .modified: return .colModified
        case .created: return .colCreated
        case .live: return .colLive
        case .bpm: return .colBPM
        case .key: return .colKey
        case .tracks: return .colTracks
        case .pluginCount: return .colPluginCount
        case .fileCount: return .colFileCount
        case .pluginsMissed: return .colPluginsMissed
        case .filesMissed: return .colFilesMissed
        case .tags: return .colTags
        case .size: return .colProjectSize
        }
    }

    /// Upstream's logical widths (px at 96 dpi) scaled to points; `nil` — the column stretches.
    var width: (min: CGFloat, ideal: CGFloat)? {
        switch self {
        case .set: return nil
        case .place: return (80, 110)
        case .modified, .created: return (76, 88)
        case .live: return (44, 56)
        case .bpm: return (44, 56)
        case .key: return (72, 96)
        case .tracks, .pluginCount, .fileCount: return (48, 60)
        case .pluginsMissed: return (80, 104)
        case .filesMissed: return (80, 96)
        case .tags: return (80, 110)
        case .size: return (60, 80)
        }
    }

    /// Numbers read better against the right edge.
    var isRightAligned: Bool {
        switch self {
        case .bpm, .tracks, .pluginCount, .fileCount, .pluginsMissed, .filesMissed, .size: return true
        default: return false
        }
    }
}

// MARK: - Sorting

/// One sort choice: a column and a direction.
struct SetSort: Equatable, Hashable, Codable, Sendable {
    var column: SetColumnID
    var descending: Bool

    /// What the list shows when no header was clicked: newest first, no arrow.
    static let fallback = SetSort(column: .modified, descending: true)
}

/// The comparators of upstream's `ColDef.Sort`. Ascending; the caller reverses the comparison
/// (not the list) for descending, so pinned groups stay where they are.
enum SetCompare {
    /// `tagsText` supplies a set's tags joined for comparing (they live in notes.cfg, not in the set).
    static func order(_ a: SetEntry, _ b: SetEntry, by column: SetColumnID,
                      tagsText: (SetEntry) -> String = { _ in "" }) -> ComparisonResult {
        switch column {
        case .set: return text(a.name, b.name)
        case .place: return text(a.place, b.place)
        case .modified: return number(a.modified, b.modified)
        case .created: return number(a.created, b.created)
        case .live: return SetFilter.compareVersion(a.shortVersion, b.shortVersion)
        case .bpm: return number(a.tempo, b.tempo)
        case .key: return emptyLast(a.key, b.key)
        case .tracks: return number(a.tracks, b.tracks)
        case .pluginCount: return number(a.plugins.count, b.plugins.count)
        case .fileCount: return number(a.totalRefs, b.totalRefs)
        // The columns are called "missed": that is what they sort by, not by the totals.
        case .pluginsMissed: return number(a.missingPlugins, b.missingPlugins)
        case .filesMissed: return number(a.missingFiles, b.missingFiles)
        case .tags: return emptyLast(tagsText(a), tagsText(b))
        case .size: return number(a.projectSize, b.projectSize)
        }
    }

    private static func text(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .numeric], locale: .current)
    }

    private static func number<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }

    /// Sets with no value always go at the end rather than being mixed in.
    private static func emptyLast(_ a: String, _ b: String) -> ComparisonResult {
        let ea = a.isEmpty, eb = b.isEmpty
        if ea != eb { return ea ? .orderedDescending : .orderedAscending }
        return text(a, b)
    }
}

/// Bridges `Table`'s header clicks to `SetSort`: the table only remembers which column was
/// clicked and in which direction; the rows are ordered by `SetsPipeline` (custom comparators,
/// pinned first), so `compare` here is only used if SwiftUI ever sorts by itself.
struct SetSortComparator: SortComparator {
    var column: SetColumnID
    var order: SortOrder = .forward

    init(_ column: SetColumnID, order: SortOrder = .forward) {
        self.column = column
        self.order = order
    }

    func compare(_ lhs: SetEntry, _ rhs: SetEntry) -> ComparisonResult {
        let result = SetCompare.order(lhs, rhs, by: column)
        return order == .forward ? result : (result == .orderedAscending ? .orderedDescending
                                             : result == .orderedDescending ? .orderedAscending : .orderedSame)
    }

    var sort: SetSort { SetSort(column: column, descending: order == .reverse) }
}
