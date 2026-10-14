// Mac-only: replays the FSEvents journal of one root from a saved event id (the startup diff scan).
import CoreServices
import Foundation

public enum FSEventsReplay {
    /// Collects what the journal recorded for `root` since `since`, up to the "history done"
    /// marker. Event paths are rebased from the resolved path FSEvents reports onto `root` as the
    /// catalog spells it. A stream that cannot be made or does not finish in time is `.unusable`.
    public static func events(root: String, since: UInt64, timeout: TimeInterval = 20) -> ReplayOutcome {
        let sink = Sink(realRoot: realPath(root), root: root)
        let retained = Unmanaged.passRetained(sink)
        var context = FSEventStreamContext(version: 0, info: retained.toOpaque(), retain: nil,
                                           release: { info in if let info { Unmanaged<Sink>.fromOpaque(info).release() } },
                                           copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [root] as CFArray,
                                               FSEventStreamEventId(since), 0.05, flags) else {
            retained.release()
            return .unusable(.replayFailed)
        }
        let queue = DispatchQueue(label: "alive.fsevents.replay", qos: .userInitiated)
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return .unusable(.replayFailed)
        }
        let finished = sink.done.wait(timeout: .now() + timeout) == .success
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        guard finished else { return .unusable(.replayFailed) }
        return .events(sink.take())
    }

    private final class Sink: @unchecked Sendable {
        let realRoot: String
        let root: String
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var list: [ReplayedEvent] = []
        private var signalled = false

        init(realRoot: String, root: String) {
            self.realRoot = realRoot
            self.root = root
        }

        func add(_ path: String, _ flags: UInt32) {
            lock.lock()
            defer { lock.unlock() }
            if !signalled { list.append(ReplayedEvent(path: rebased(path), flags: flags)) }
            if flags & UInt32(kFSEventStreamEventFlagHistoryDone) != 0, !signalled {
                signalled = true
                done.signal()
            }
        }

        func take() -> [ReplayedEvent] {
            lock.lock(); defer { lock.unlock() }
            return list
        }

        private func rebased(_ path: String) -> String {
            guard realRoot != root, path == realRoot || path.hasPrefix(realRoot + "/") else { return path }
            return root + path.dropFirst(realRoot.count)
        }
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info else { return }
        let sink = Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue()
        let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
        let flagList = Array(UnsafeBufferPointer(start: flags, count: count))
        for (path, flag) in zip(list, flagList) { sink.add(path, UInt32(flag)) }
    }

    private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
