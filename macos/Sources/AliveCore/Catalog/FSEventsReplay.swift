// Mac-only: replays the FSEvents journal of one root from a saved event id (the startup diff scan).
import CoreServices
import Foundation

public enum FSEventsReplay {
    /// A busy sample tree can produce millions of file events. Replay is an optimization:
    /// fall back to a bounded-memory full walk instead of buffering the whole journal.
    static let maxBufferedEvents = 16_384
    /// Collects what the journal recorded for `root` since `since`, up to the "history done"
    /// marker. Event paths are rebased from the resolved path FSEvents reports onto `root` as the
    /// catalog spells it. A stream that cannot be made or does not finish in time is `.unusable`.
    public static func events(root: String, since: UInt64, timeout: TimeInterval = 20,
                              isCancelled: () -> Bool = { false }) -> ReplayOutcome {
        guard !isCancelled() else { return .unusable(.replayFailed) }
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
        let finished = sink.wait(timeout: timeout, isCancelled: isCancelled)
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        queue.sync {}             // finish any callback that already borrowed the sink
        FSEventStreamRelease(stream)
        guard finished else { return .unusable(.replayFailed) }
        return sink.outcome()
    }

    final class Sink: @unchecked Sendable {
        let realRoot: String
        let root: String
        private let done = DispatchSemaphore(value: 0)
        private let maxEvents: Int
        private let lock = NSLock()
        private var list: [ReplayedEvent] = []
        private var signalled = false
        private var failure: FullScanReason?

        init(realRoot: String, root: String, maxEvents: Int = FSEventsReplay.maxBufferedEvents) {
            self.realRoot = realRoot
            self.root = root
            self.maxEvents = max(1, maxEvents)
        }

        @discardableResult
        func add(_ path: String, _ flags: UInt32) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !signalled else { return false }
            if flags & DiffScan.unreliable != 0 {
                failure = .journalUnreliable
            } else if flags & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 {
                signalled = true
                done.signal()
                return false
            } else if list.count >= maxEvents {
                failure = .tooManyChanges
            } else {
                list.append(ReplayedEvent(path: rebased(path), flags: flags))
                return true
            }
            list.removeAll(keepingCapacity: false)
            signalled = true
            done.signal()
            return false
        }

        func outcome() -> ReplayOutcome {
            lock.lock(); defer { lock.unlock() }
            return failure.map(ReplayOutcome.unusable) ?? .events(list)
        }

        /// A superseded launch scan must not wait 20 seconds per remaining root. Each wait
        /// checks its cancellation flag at least every 20 ms; no event stream has to be killed.
        func wait(timeout: TimeInterval, isCancelled: () -> Bool) -> Bool {
            let deadline = DispatchTime.now() + max(0, timeout)
            while !isCancelled() {
                let next = min(deadline, .now() + 0.02)
                if done.wait(timeout: next) == .success { return !isCancelled() }
                if DispatchTime.now() >= deadline { return false }
            }
            return false
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
        let flagList = UnsafeBufferPointer(start: flags, count: count)
        for (path, flag) in zip(list, flagList) {
            if !sink.add(path, UInt32(flag)) { break }
        }
    }

    private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
