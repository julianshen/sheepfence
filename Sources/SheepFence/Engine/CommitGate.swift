import Foundation

/// Cancellation may prevent a queued transaction, but cannot undo a begun durable commit.
final class CommitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var begun = false
    func cancel() { lock.lock(); defer { lock.unlock() }; if !begun { cancelled = true } }
    func begin() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        begun = true
    }
}
