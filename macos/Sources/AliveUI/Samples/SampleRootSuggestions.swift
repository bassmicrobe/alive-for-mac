// Port of RootsDialog.LiveSuggestions (src/RootsDialog.cs) for sample folders: one-click folders
// found from what Live itself knows about this machine.
import Foundation
import AliveCore

struct SampleRootSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case place(String)      // a folder of Live's browser sidebar, by the name Live gives it
        case userLibrary, packs, coreLibrary
    }

    let kind: Kind
    let path: String
    var id: String { path }

    var title: String {
        switch kind {
        case .place(let name): return name
        case .userLibrary: return SamplesStrings.suggestionLibrary.s
        case .packs: return SamplesStrings.suggestionPacks.s
        case .coreLibrary: return SamplesStrings.suggestionCore.s
        }
    }

    /// `~/Music/Ableton/User Library` for paths under the home folder.
    func display(home: String = NSHomeDirectory()) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

enum SampleRootSuggestions {
    /// Live's Places (except those that are project folders already), the User Library, the packs
    /// folder — or, without one, the parents of the installed packs — and the Core Library. Only
    /// folders that exist and are not yet in the library (nor inside a folder of it).
    static func make(env: LiveEnvironment, projectRoots: [String], existing: [String],
                     isDirectory: (String) -> Bool = RootSuggestions.directoryExists) -> [SampleRootSuggestion] {
        var candidates: [SampleRootSuggestion] = []
        for place in env.places {
            let isProjects = projectRoots.contains { SampleIndex.containsPath([$0], place.path) || SampleIndex.inside(place.path, $0) }
            if !isProjects { candidates.append(SampleRootSuggestion(kind: .place(place.name), path: place.path)) }
        }
        candidates.append(SampleRootSuggestion(kind: .userLibrary, path: env.userLibrary))
        if !env.packsFolder.isEmpty {
            candidates.append(SampleRootSuggestion(kind: .packs, path: env.packsFolder))
        } else {
            for (name, path) in env.packs.sorted(by: { $0.key < $1.key }) where name != "Core Library" {
                candidates.append(SampleRootSuggestion(kind: .packs, path: (path as NSString).deletingLastPathComponent))
            }
        }
        candidates.append(SampleRootSuggestion(kind: .coreLibrary, path: env.coreLibrary))

        var result: [SampleRootSuggestion] = []
        for c in candidates where !c.path.isEmpty && isDirectory(c.path) {
            let covered = existing.contains { SampleIndex.containsPath([$0], c.path) || SampleIndex.inside(c.path, $0) }
            if covered || SampleIndex.containsPath(result.map(\.path), c.path) { continue }
            result.append(c)
        }
        return result
    }
}
