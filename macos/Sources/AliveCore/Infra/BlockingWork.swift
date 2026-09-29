// Mac-only: runs blocking work (a scan with concurrentPerform, copying gigabytes) off the
// cooperative thread pool. Swift's `Task.detached` shares its few threads with every other
// async task of the app; a job that blocks them for minutes starves the rest.
import Foundation

public enum BlockingWork {
    /// A dedicated concurrent queue: several long jobs may run at once (a scan and a sample
    /// walk), and none of them holds a cooperative thread.
    private static let queue = DispatchQueue(label: "alive.blocking-work", qos: .utility, attributes: .concurrent)

    /// Runs `work` on the dedicated queue and resumes with its result. Cancelling the calling
    /// task sets the flag `work` receives as `isCancelled`; the work stops at its next check
    /// (it is never killed in the middle of a step).
    public static func run<T: Sendable>(
        _ work: @escaping @Sendable (_ isCancelled: @escaping @Sendable () -> Bool) throws -> T
    ) async throws -> T {
        let flag = CancelFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
                queue.async {
                    do { cont.resume(returning: try work({ flag.isSet })) } catch { cont.resume(throwing: error) }
                }
            }
        } onCancel: { flag.set() }
    }

    /// The same for work that cannot fail.
    public static func run<T: Sendable>(
        _ work: @escaping @Sendable (_ isCancelled: @escaping @Sendable () -> Bool) -> T
    ) async -> T {
        let flag = CancelFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
                queue.async { cont.resume(returning: work({ flag.isSet })) }
            }
        } onCancel: { flag.set() }
    }
}
