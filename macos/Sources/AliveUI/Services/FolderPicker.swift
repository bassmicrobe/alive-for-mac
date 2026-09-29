// Mac-only: NSOpenPanel for folders (upstream: FolderBrowserDialog in RootsDialog).
import AppKit

@MainActor
enum FolderPicker {
    /// Asks for one or more folders; empty when cancelled.
    static func chooseFolders(message: String, prompt: String) -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.message = message
        panel.prompt = prompt
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map(\.path)
    }
}
