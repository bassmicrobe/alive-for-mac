// Port of src/FolderWatch.cs (FileSystemWatcher → FSEvents)
import CoreServices
import Foundation

/// Watches the catalog roots and reports when something there has changed — so that a new set
/// appears in the list on its own, without ⌘R.
///
/// The event always comes with a delay: one save from Live is not one change on disk but a burst
/// of them (a temporary file, a rename, a folder update), and scanning on each would mean walking
/// the whole tree several times in a row. The countdown restarts from every new event, so during
/// an export or a recording, when the disk is written to continuously, the rescan simply waits
/// for quiet.
///
/// What counts (upstream ran two watchers per root for this): an `.als` that appears, goes away,
/// is renamed or is written to (the set was re-saved, it has a different tempo and plugins now),
/// and anything at all that appears, disappears or is renamed (a new project folder, a deleted
/// project, a fresh render next to a set). Content changes of other files are ignored — otherwise
/// every recorded sample would reset the countdown, and while working in Live the refresh would
/// never come at all.
public final class FolderWatch: @unchecked Sendable {
    /// Called on a private queue once the disk has been quiet for `settle` seconds.
    public var onChanged: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return callback }
        set { lock.lock(); callback = newValue; lock.unlock() }
    }

    private let settle: TimeInterval
    private let latency: TimeInterval
    private let queue = DispatchQueue(label: "alive.folderwatch", qos: .utility)
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    /// Real paths of the watched roots (FSEvents reports resolved paths).
    private var realRoots: [String] = []

    /// `settle`: quiet time before `onChanged` fires (upstream 3 s). `latency`: FSEvents' own
    /// coalescing window.
    public init(settle: TimeInterval = 3, latency: TimeInterval = 0.2) {
        self.settle = settle
        self.latency = latency
    }

    deinit { stop() }

    public var isWatching: Bool { lock.lock(); defer { lock.unlock() }; return stream != nil }

    /// Points the watch at a new set of roots. Roots excluded from scanning are skipped: the
    /// catalog does not show their contents anyway, and there is no reason to be woken from there.
    public func watch(roots: [String], disabled: [String] = []) {
        stop()
        let off = Set(disabled.map { Self.normalized($0) })
        let live = roots.filter { root in
            guard !off.contains(Self.normalized(root)) else { return false }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: root, isDirectory: &isDir) && isDir.boolValue
        }
        guard !live.isEmpty else { return }

        let retainedBox = Unmanaged.passRetained(Box(owner: self))
        var context = FSEventStreamContext(
            version: 0, info: retainedBox.toOpaque(),
            retain: nil,
            release: { info in if let info { Unmanaged<Box>.fromOpaque(info).release() } },
            copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, Self.callback, &context, live as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
            Diag.info("folder watch: could not create an event stream for \(live.count) roots")
            retainedBox.release()   // no stream took the reference
            return
        }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            Diag.info("folder watch: could not start the event stream")
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return
        }
        lock.lock()
        stream = created
        realRoots = live.map(Self.realPath)
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let old = stream
        stream = nil
        realRoots = []
        pending?.cancel()
        pending = nil
        lock.unlock()
        guard let old else { return }
        FSEventStreamStop(old)
        FSEventStreamInvalidate(old)
        FSEventStreamRelease(old)
    }

    // MARK: - Events

    private final class Box {
        weak var owner: FolderWatch?
        init(owner: FolderWatch) { self.owner = owner }
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info else { return }
        let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
        let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
        let flagList = Array(UnsafeBufferPointer(start: flags, count: count))
        box.owner?.handle(paths: list, flags: flagList)
    }

    private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        lock.lock()
        let roots = realRoots
        lock.unlock()
        for (path, flag) in zip(paths, flags) where Self.isRelevant(path: path, flags: flag, roots: roots) {
            bump()
            return
        }
    }

    /// Whether one event should restart the countdown. Pure, so the rules can be tested without
    /// touching a disk.
    static func isRelevant(path: String, flags: FSEventStreamEventFlags, roots: [String] = []) -> Bool {
        // Events were lost or the tree must be rewalked: all the more reason to rescan
        // (upstream: the watcher's Error event).
        let overflow = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagRootChanged)
        if flags & overflow != 0 { return true }

        // The rescue helper's probes do not wake the catalog: it does not show them anyway
        // (see FolderScan.find), and during an investigation they appear and disappear on every
        // probe.
        if path.lowercased().hasSuffix(FolderScan.probeSuffix) { return false }
        // Hidden entries (.DS_Store, ._AppleDouble…) are not scanned either.
        if isHidden(path, below: roots) { return false }

        let structural = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated
            | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed)
        if flags & structural != 0 { return true }
        let touched = FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
        return flags & touched != 0 && path.lowercased().hasSuffix(".als")
    }

    private static func isHidden(_ path: String, below roots: [String]) -> Bool {
        let root = roots.first { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        let relative = root.map { String(path.dropFirst($0.count)) } ?? path
        return relative.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    private func bump() {
        lock.lock()
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.fire() }
        pending = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + settle, execute: item)
    }

    private func fire() {
        lock.lock()
        pending = nil
        let handler = callback
        lock.unlock()
        handler?()
    }

    // MARK: - Paths

    private static func normalized(_ path: String) -> String {
        (path as NSString).standardizingPath.lowercased()
    }

    private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
