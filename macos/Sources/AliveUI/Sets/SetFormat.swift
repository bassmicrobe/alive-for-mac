// Mac-only: cell text for the Sets list (upstream: the formatting inside SetsGrid in MainForm.cs).
import Foundation
import AliveCore

enum SetFormat {
    /// "128" / "127.5"; empty when the set has no tempo.
    static func tempo(_ bpm: Double) -> String {
        guard bpm > 0 else { return "" }
        return bpm == bpm.rounded() ? String(Int(bpm)) : String(format: "%.1f", bpm)
    }

    /// "1.4 GB"; empty for zero.
    static func size(_ bytes: Int64, locale: Locale = Localizer.shared.locale) -> String {
        guard bytes > 0 else { return "" }
        return ByteSize.string(bytes, locale: locale)
    }

    /// Modified time in the UI language ("2025/03/07 21:14" / "Mar 7, 2025, 9:14 PM").
    static func modified(_ date: Date, locale: Locale = Localizer.shared.locale) -> String {
        guard date > .distantPast else { return "" }
        return date.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
    }

    /// "2025-03-07" in local time (upstream's date columns); empty when unknown.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        guard date > .distantPast else { return "" }
        return SetFilter.formatDate(date, calendar: calendar)
    }

    /// How many of `versions` were saved on each calendar day (the key is the start of the day).
    static func dayCounts(of versions: [SetEntry], calendar: Calendar = .current) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for v in versions { counts[calendar.startOfDay(for: v.modified), default: 0] += 1 }
        return counts
    }

    /// A version's date in the Versions block, with the time when another version of the folder was
    /// saved the same day: two equal dates told nothing apart (9ce4b4b). `version` is one of the
    /// `all` that `dayCounts` counted.
    static func versionStamp(_ version: SetEntry, among all: [SetEntry], calendar: Calendar = .current) -> String {
        versionStamp(version, dayCounts: dayCounts(of: all, calendar: calendar), calendar: calendar)
    }

    /// The same with the per-day counts made once for the whole block, not once per row.
    static func versionStamp(_ version: SetEntry, dayCounts: [Date: Int], calendar: Calendar = .current) -> String {
        let date = day(version.modified, calendar: calendar)
        guard !date.isEmpty, dayCounts[calendar.startOfDay(for: version.modified), default: 0] > 1 else { return date }
        let time = calendar.dateComponents([.hour, .minute], from: version.modified)
        return date + String(format: " %02d:%02d", time.hour ?? 0, time.minute ?? 0)
    }

    /// "1 set" / "3 sets": English needs the singular form, Japanese carries the same text in both.
    static func plural(_ n: Int, one: SetsStrings, many: SetsStrings) -> String {
        (n == 1 ? one : many).f(n)
    }

    /// The toolbar's "553 projects · 754 sets", with the singular forms ("1 project · 1 set").
    static func shownSummary(projects: Int, sets: Int) -> String {
        if sets == 1 { return SetsStrings.shownSummaryOne.s }
        if projects == 1 { return SetsStrings.shownSummaryOneProject.f(sets) }
        return SetsStrings.shownSummary.f(projects, sets)
    }

    /// The Filters window's counter: the number of rows the list shows (search applied, one row per
    /// project when versions are folded), so the two never disagree (9ce4b4b).
    static func matches(_ count: Int, perProject: Bool) -> String {
        perProject ? plural(count, one: .fltMatchesProject1, many: .fltMatchesProjects)
                   : plural(count, one: .fltMatchesSet1, many: .fltMatchesSets)
    }

    /// Names (and paths) from real libraries often start with a space; shown as they are, that
    /// looks like broken layout. Display only: the exact text goes into help and file operations.
    static func displayName(_ text: String) -> String {
        String(text.drop(while: { $0.isWhitespace }))
    }

    /// "/Users/me/Music/Live" as "~/Music/Live" (the same form the folder suggestions use); the
    /// absolute path stays in help text and accessibility values.
    static func homeAbbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// Plugin and file counts: nothing rather than "0".
    static func count(_ n: Int) -> String { n > 0 ? String(n) : "" }
}
