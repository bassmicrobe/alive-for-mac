// Mac-only: keeps the sets list's column layout in `sets-columns.json` next to the settings.
// Deviation from upstream, which packs the layout into one `setcolumns=` string in settings.cfg:
// here SwiftUI's own `TableColumnCustomization` (visibility, order, widths) is stored as JSON.
import Foundation
import SwiftUI
import AliveCore

struct SetsColumnLayout: Codable {
    static let currentVersion = 1

    var version = SetsColumnLayout.currentVersion
    var columns = TableColumnCustomization<SetEntry>()
    /// The header the list is sorted by; nil — newest first.
    var sort: SetSort?
}

enum SetsColumnStore {
    static let fileName = "sets-columns.json"

    /// A missing, unreadable or newer-format file gives the default layout (and a log line
    /// when it existed but could not be read).
    static func load(dir: String) -> SetsColumnLayout {
        let path = AppHome.file(fileName, in: dir)
        guard let data = FileManager.default.contents(atPath: path) else { return SetsColumnLayout() }
        do {
            let layout = try JSONDecoder().decode(SetsColumnLayout.self, from: data)
            return layout.version == SetsColumnLayout.currentVersion ? layout : SetsColumnLayout()
        } catch {
            Diag.fail("read \(fileName)", error)
            return SetsColumnLayout()
        }
    }

    @discardableResult
    static func save(_ layout: SetsColumnLayout, dir: String) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try AppHome.writeAtomically(try encoder.encode(layout), to: AppHome.file(fileName, in: dir))
            return true
        } catch {
            Diag.fail("write \(fileName)", error)
            return false
        }
    }
}
