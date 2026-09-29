// Port of the counting and Live suggestions of src/RootsDialog.cs: what a folder holds (the number
// next to each folder of the list) and the folders Live itself knows about.
import Foundation
import AliveCore

enum RootCounter {
    /// How many sets a folder holds — with exactly the walk the scan later uses, or the number
    /// would disagree with what ends up in the catalog. -1: the folder will not open.
    static func countSets(in folder: String, isCancelled: () -> Bool = { false }) -> Int {
        guard RootSuggestions.directoryExists(folder) else { return -1 }
        let result = FolderScan.find(root: folder, ext: ".als", includeBackups: false,
                                     onFile: { _ in }, isCancelled: isCancelled)
        return result.rootFailed ? -1 : result.files
    }

    /// Extensions Live can load as a sample (upstream SampleIndex.Exts).
    static let sampleExtensions: Set<String> = ["wav", "aif", "aiff", "flac", "ogg", "mp3", "m4a", "rx2", "rex"]

    /// How many samples a folder holds. -1: the folder will not open.
    static func countSamples(in folder: String, isCancelled: () -> Bool = { false }) -> Int {
        guard RootSuggestions.directoryExists(folder) else { return -1 }
        var todo = [folder], count = 0
        var first = true
        while let dir = todo.popLast() {
            if isCancelled() { break }
            guard let entries = FolderScan.list(dir) else {
                if first { return -1 }
                continue
            }
            first = false
            for entry in entries {
                if entry.isDirectory {
                    if entry.isPackage || entry.name.lowercased().hasSuffix(".app") { continue }
                    todo.append(dir + "/" + entry.name)
                } else if sampleExtensions.contains((entry.name as NSString).pathExtension.lowercased()) {
                    count += 1
                }
            }
        }
        return count
    }
}

/// A folder Live knows about, offered in the sample folders page.
struct LiveFolderSuggestion: Equatable, Identifiable {
    var title: String
    var path: String
    /// A project folder: offered, but marked as such.
    var isProjects = false
    /// A separator above it in the menu.
    var startsGroup = false
    var id: String { path }
}

enum LiveFolderSuggestions {
    /// Live's Places, then the User Library, the packs and the Core Library — only folders that
    /// exist, without repeats (upstream `RootsDialog.LiveSuggestions`).
    static func make(env: LiveEnvironment, projectRoots: [String],
                     isDirectory: (String) -> Bool = RootSuggestions.directoryExists) -> [LiveFolderSuggestion] {
        var list: [LiveFolderSuggestion] = []
        for place in env.places {
            var s = LiveFolderSuggestion(title: place.name, path: place.path)
            s.isProjects = projectRoots.contains { covers(root: $0, path: place.path) || covers(root: place.path, path: $0) }
            list.append(s)
        }
        let group = list.count
        func addLibrary(_ title: String, _ path: String) {
            guard !path.isEmpty, isDirectory(path), !list.contains(where: { same($0.path, path) }) else { return }
            list.append(LiveFolderSuggestion(title: title, path: path))
        }
        addLibrary("User Library", env.userLibrary)
        if !env.packsFolder.isEmpty {
            addLibrary("Packs", env.packsFolder)
        } else {
            for (name, path) in env.packs where name != "Core Library" {
                addLibrary("Packs", (path as NSString).deletingLastPathComponent)
            }
        }
        addLibrary("Core Library", env.coreLibrary)
        if group < list.count { list[group].startsGroup = true }
        return list
    }

    static func same(_ a: String, _ b: String) -> Bool {
        (a as NSString).standardizingPath.caseInsensitiveCompare((b as NSString).standardizingPath) == .orderedSame
    }

    /// `path` is `root` or lies inside it.
    static func covers(root: String, path: String) -> Bool {
        let r = (root as NSString).standardizingPath.lowercased(), p = (path as NSString).standardizingPath.lowercased()
        return p == r || p.hasPrefix(r.hasSuffix("/") ? r : r + "/")
    }
}
