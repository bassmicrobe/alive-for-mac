// Mac-only: replaces upstream's `explorer /select`.
import Foundation
import AppKit

enum FinderError: Error {
    case missing(String)
    case failed(String)
}

@MainActor
enum Finder {
    /// Reveals the file (or folder) selected in a Finder window.
    static func reveal(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { throw FinderError.missing(path) }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Opens the folder itself.
    static func openFolder(path: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw FinderError.missing(path)
        }
        let url = URL(fileURLWithPath: path)
        // A file was given: show it instead of trying to "open" it as a folder.
        guard isDirectory.boolValue else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        guard NSWorkspace.shared.open(url) else { throw FinderError.failed(path) }
    }
}
