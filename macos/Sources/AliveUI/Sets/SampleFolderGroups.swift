// Port of MainForm.SampleFoldersOf (src/SamplesTab.cs): which library folders a set takes its
// samples from and how many from each — the inspector's "Sample folders". Upstream asks its
// SampleIndex; the index of this port belongs to the Samples tab, so this works from the
// samples the set recorded and the same roots the index scans (User Library, packs, Core
// Library and the sample folders of the settings).
import Foundation
import AliveCore

struct SampleFolderGroup: Equatable, Identifiable {
    /// The top folder under a root: what `SamplesModel.showFolder` is called with.
    var folder: String
    /// "Samples/Drums": under its root's own name, so two roots both called "Samples" do not read alike.
    var title: String
    var count: Int
    var id: String { folder }
}

enum SampleFolderGroups {
    /// The library roots for a machine: Live's own folders plus the user's sample folders.
    static func roots(env: LiveEnvironment, sampleRoots: [String], disabled: [String]) -> [String] {
        var roots = [env.userLibrary + (env.userLibrary.isEmpty ? "" : "/Samples")]
        if !env.packsFolder.isEmpty {
            roots.append(env.packsFolder)
        } else {
            roots.append(contentsOf: env.packs.values.map { ($0 as NSString).deletingLastPathComponent })
        }
        roots.append(env.coreLibrary)
        roots.append(contentsOf: sampleRoots.filter { root in
            !disabled.contains { $0.caseInsensitiveCompare(root) == .orderedSame }
        })
        var seen = Set<String>()
        return roots.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Groups the sample paths by the first folder below the root each lies in (the root itself for
    /// files right in it), most samples first. Paths outside every root are not counted: a file
    /// that is in no library belongs to no folder.
    static func make(samples: [String], roots: [String]) -> [SampleFolderGroup] {
        let normalized = roots.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        var counts: [String: (title: String, count: Int)] = [:]
        for sample in samples {
            guard let root = longestRoot(containing: sample, in: normalized) else { continue }
            let below = String(sample.dropFirst(root.count + 1))
            let parts = below.split(separator: "/", omittingEmptySubsequences: true)
            // The sample's own name is not a folder.
            let folder: String, title: String
            if parts.count > 1 {
                folder = root + "/" + parts[0]
                title = SampleFolderGroups.name(of: root) + "/" + parts[0]
            } else {
                folder = root
                title = root
            }
            counts[folder, default: (title, 0)].count += 1
        }
        return counts.map { SampleFolderGroup(folder: $0.key, title: $0.value.title, count: $0.value.count) }
            .sorted { a, b in
                a.count != b.count ? a.count > b.count
                    : a.title.compare(b.title, options: [.caseInsensitive, .numeric]) == .orderedAscending
            }
    }

    private static func longestRoot(containing path: String, in roots: [String]) -> String? {
        let lower = path.lowercased()
        return roots.filter { lower.hasPrefix($0.lowercased() + "/") }.max { $0.count < $1.count }
    }

    private static func name(of root: String) -> String {
        let n = (root as NSString).lastPathComponent
        return n.isEmpty ? root : n
    }
}
