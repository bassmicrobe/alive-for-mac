// Mac-only: wraps ProjectIndex: launch scan, rescan with progress (placeholder — replaced by the feature's implementer).
import Foundation
import Observation

@MainActor
@Observable
final class CatalogModel {
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    private(set) var setCount = 0
    private(set) var isScanning = false
    /// 0...1 while `isScanning`.
    private(set) var progress = 0.0

    func rescan() {}
}
