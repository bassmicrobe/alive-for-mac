// Mac-only: sample folders on drives that come and go.
import Foundation
import AliveCore

extension SamplesModel {
    /// Whether a sample folder lives on a volume that is not connected right now. Its cached tree
    /// stays in the library (it is never walked as empty), and the sets' use of its samples still
    /// counts. Observes the mounted volumes, so a badge updates by itself.
    func isOffline(root: String) -> Bool {
        VolumeState.isOffline(root, mounted: app.catalog.mountedVolumes)
    }

    /// A volume came back: walk the folders again so a root that was kept from the cache is read
    /// for real. (A volume going away needs nothing: the walk skips its roots.)
    func volumesChanged(appeared: Set<String>) {
        guard started, isLoaded, !appeared.isEmpty else { return }
        let touched = effectiveRoots.contains { VolumeState.volumeName(of: $0).map(appeared.contains) ?? false }
        if touched { startScan(manual: false) }
    }
}
