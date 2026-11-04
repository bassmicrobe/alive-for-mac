// Mac-only: the pasteboard calls of the Sets tab (upstream: Clipboard.SetText in MainForm.cs and
// DetailPanel.cs), in one place so the views stay free of AppKit.
import AppKit

enum SetsClipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
