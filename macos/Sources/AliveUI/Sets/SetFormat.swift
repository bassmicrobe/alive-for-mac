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
    static func size(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Modified time in the UI language ("2025/03/07 21:14" / "Mar 7, 2025, 9:14 PM").
    static func modified(_ date: Date, locale: Locale = Localizer.shared.locale) -> String {
        guard date > .distantPast else { return "" }
        return date.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
    }

    /// Plugin and file counts: nothing rather than "0".
    static func count(_ n: Int) -> String { n > 0 ? String(n) : "" }
}
