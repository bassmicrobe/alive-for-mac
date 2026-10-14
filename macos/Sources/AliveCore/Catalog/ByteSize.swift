// Mac-only: file sizes in a given language. `ByteCountFormatter` follows the system locale, which
// shows "248 バイト" in an English UI; this takes the locale from the caller.
import Foundation

public enum ByteSize {
    /// "12 MB" / "248 bytes" / "248 バイト"; "0 KB" rather than "Zero KB".
    public static func string(_ bytes: Int64, locale: Locale) -> String {
        bytes.formatted(ByteCountFormatStyle(style: .file, allowedUnits: .all, spellsOutZero: false,
                                             includesActualByteCount: false).locale(locale))
    }
}
