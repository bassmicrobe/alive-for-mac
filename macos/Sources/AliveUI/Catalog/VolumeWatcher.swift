// Mac-only: tells the catalog when a volume was mounted or unmounted (NSWorkspace), after the
// burst of notifications a plugged drive causes has settled.
import AppKit

@MainActor
final class VolumeWatcher {
    private let center: NotificationCenter
    private let debounce: Duration
    private var tokens: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    var onChange: (() -> Void)?

    /// `center` is injectable so a test can post the notifications itself.
    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter, debounce: Duration = .seconds(1.5)) {
        self.center = center
        self.debounce = debounce
    }

    func start() {
        guard tokens.isEmpty else { return }
        let names: [Notification.Name] = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification]
        tokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.bump() }
            }
        }
    }

    func stop() {
        tokens.forEach(center.removeObserver)
        tokens = []
        pending?.cancel()
        pending = nil
    }

    private func bump() {
        pending?.cancel()
        pending = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
}
