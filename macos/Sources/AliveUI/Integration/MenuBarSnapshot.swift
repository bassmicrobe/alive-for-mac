// Mac-only: what the menu bar extra shows, computed from plain values so it can be tested.
import Foundation
import AliveCore

struct MenuBarSnapshot: Equatable {
    static let recentLimit = 8

    var savesToday: Int
    var streak: Int
    /// Pinned sets, newest first.
    var pinned: [SetEntry]
    /// The most recently modified projects (one per project folder), pinned ones included.
    var recent: [SetEntry]

    static func make(sets: [SetEntry], pins: Set<String>, activity: Activity, now: Date = Date()) -> MenuBarSnapshot {
        let live = sets.filter { !$0.isBackup }
        let pinned = live.filter { pins.contains($0.path) }.sorted { $0.modified > $1.modified }
        var seenDirs = Set<String>()
        var recent: [SetEntry] = []
        for set in live.sorted(by: { $0.modified > $1.modified }) {
            guard seenDirs.insert(set.projectDir.lowercased()).inserted else { continue }
            recent.append(set)
            if recent.count == recentLimit { break }
        }
        return MenuBarSnapshot(savesToday: activity.saves(on: now), streak: activity.currentStreak,
                               pinned: pinned, recent: recent)
    }
}
