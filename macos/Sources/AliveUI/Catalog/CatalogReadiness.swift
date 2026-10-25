// Mac-only: retained rows keep their saved facts, but a confirmed missing root cannot be ready now.
import AliveCore

enum CatalogReadiness {
    /// A volatile overlay: never changes the saved catalog or probes paths on the main thread.
    /// Offline roots are not in `missingRoots`; their existing volume status remains untouched.
    static func statuses(_ saved: [String: SetStatus], after scan: ScanStats?) -> [String: SetStatus] {
        guard let scan, scan.retainedPreviousCatalog, !scan.missingRoots.isEmpty else { return saved }
        let missing = Set(scan.missingRoots.map { root in
            var key = root.lowercased()
            while key.count > 1, key.hasSuffix("/") { key.removeLast() }
            return key
        })
        var result = saved
        for (path, status) in saved where hasMissingAncestor(path, roots: missing) {
            var unavailable = status
            unavailable.isUnreadable = true
            result[path] = unavailable
        }
        return result
    }

    /// Compare whole ancestors, not prefixes (`/Library-other` is not under `/Library`).
    /// A set of root keys avoids checking every root against every catalog row.
    private static func hasMissingAncestor(_ path: String, roots: Set<String>) -> Bool {
        var ancestor = path.lowercased()
        while let slash = ancestor.lastIndex(of: "/") {
            ancestor = slash == ancestor.startIndex ? "/" : String(ancestor[..<slash])
            if roots.contains(ancestor) { return true }
            if ancestor == "/" { break }
        }
        return false
    }
}
