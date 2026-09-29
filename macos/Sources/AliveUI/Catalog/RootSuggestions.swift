// Port of RootsDialog.LiveSuggestions (src/RootsDialog.cs), for project folders: one-click folders
// found from what Live itself knows about this machine.
import Foundation
import AliveCore

struct RootSuggestion: Identifiable, Equatable {
    let path: String
    var id: String { path }
    /// "Ableton", "Music" …: the folder's own name.
    var title: String { (path as NSString).lastPathComponent }
    /// `~/Music/Ableton` for paths under the home folder.
    func display(home: String = NSHomeDirectory()) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

enum RootSuggestions {
    /// `~/Music/Ableton`, the parent of Live's User Library, and Live's Places — only folders that
    /// exist and are not yet scanned (nor inside a scanned folder).
    static func make(env: LiveEnvironment, existingRoots: [String], home: String = NSHomeDirectory(),
                     isDirectory: (String) -> Bool = RootSuggestions.directoryExists) -> [RootSuggestion] {
        var candidates = [home + "/Music/Ableton"]
        if !env.userLibrary.isEmpty { candidates.append((env.userLibrary as NSString).deletingLastPathComponent) }
        candidates.append(contentsOf: env.places.map(\.path))

        var result: [RootSuggestion] = []
        var seen = Set<String>()
        for raw in candidates where !raw.isEmpty {
            let path = (raw as NSString).standardizingPath
            guard path != home, path != "/", isDirectory(path), seen.insert(path.lowercased()).inserted,
                  !existingRoots.contains(where: { covers(root: $0, path: path) }) else { continue }
            result.append(RootSuggestion(path: path))
        }
        return result
    }

    static func directoryExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func covers(root: String, path: String) -> Bool {
        let r = (root as NSString).standardizingPath.lowercased(), p = path.lowercased()
        return p == r || p.hasPrefix(r.hasSuffix("/") ? r : r + "/")
    }
}
