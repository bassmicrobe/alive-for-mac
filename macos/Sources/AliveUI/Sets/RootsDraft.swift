// Port of the editing state of src/RootsDialog.cs: the two pages (projects, samples) are edited as a
// draft and applied together by "Scan" — one rescan for any number of edits. The counts are
// walked in the background and kept per folder, so switching pages does not walk a tree twice.
import Foundation
import Observation

@MainActor
@Observable
final class RootsDraft {
    struct Page: Equatable {
        var roots: [String] = []
        var disabled: [String] = []

        func isEnabled(_ root: String) -> Bool { !disabled.contains { LiveFolderSuggestions.same($0, root) } }

        func index(of root: String) -> Int? { roots.firstIndex { LiveFolderSuggestions.same($0, root) } }

        /// Switched on but lying inside another switched-on folder of the list: the walk takes it
        /// as part of that one (used by the samples page).
        func isNested(_ root: String) -> Bool {
            roots.contains { other in
                !LiveFolderSuggestions.same(other, root) && isEnabled(other)
                    && LiveFolderSuggestions.covers(root: other, path: root)
            }
        }

        @discardableResult
        mutating func add(_ path: String) -> Bool {
            guard index(of: path) == nil else {
                disabled.removeAll { LiveFolderSuggestions.same($0, path) }
                return false
            }
            roots.append(path)
            return true
        }

        mutating func remove(_ root: String) {
            roots.removeAll { LiveFolderSuggestions.same($0, root) }
            disabled.removeAll { LiveFolderSuggestions.same($0, root) }
        }

        mutating func set(_ root: String, enabled: Bool) {
            disabled.removeAll { LiveFolderSuggestions.same($0, root) }
            if !enabled { disabled.append(root) }
        }
    }

    var kind: RootsKind
    var projects: Page
    var samples: Page
    private let original: (projects: Page, samples: Page)

    /// -1: would not open; absent: still counting.
    private(set) var counts: [String: Int] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(kind: RootsKind, projects: Page, samples: Page) {
        self.kind = kind
        self.projects = projects
        self.samples = samples
        original = (projects, samples)
    }

    var page: Page {
        get { kind == .projects ? projects : samples }
        set { if kind == .projects { projects = newValue } else { samples = newValue } }
    }

    var projectsChanged: Bool { projects != original.projects }
    var samplesChanged: Bool { samples != original.samples }
    var hasChanges: Bool { projectsChanged || samplesChanged }

    /// Scan may be pressed with nothing in the sample list (no sample folders is a state), but not
    /// with no project folders (that is only a first run not finished yet).
    var canApply: Bool { !projects.roots.isEmpty }

    func count(for root: String) -> Int? { counts[key(kind, root)] }

    /// Starts the count of `root` unless one is running or done.
    func ensureCount(_ root: String) {
        let kind = kind, k = key(kind, root)
        guard counts[k] == nil, tasks[k] == nil else { return }
        tasks[k] = Task { [weak self] in
            let walk = Task.detached(priority: .utility) { () -> Int in
                let cancelled: () -> Bool = { Task.isCancelled }
                return kind == .projects ? RootCounter.countSets(in: root, isCancelled: cancelled)
                                         : RootCounter.countSamples(in: root, isCancelled: cancelled)
            }
            // The walk is a detached task: cancelling the caller has to be passed on by hand.
            let n = await withTaskCancellationHandler { await walk.value } onCancel: { walk.cancel() }
            guard !Task.isCancelled, let self else { return }
            self.counts[k] = n
            self.tasks[k] = nil
        }
    }

    /// The sheet closed: stop hammering the disk.
    func cancelCounting() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
    }

    private func key(_ kind: RootsKind, _ root: String) -> String {
        kind.rawValue + ":" + (root as NSString).standardizingPath.lowercased()
    }
}
