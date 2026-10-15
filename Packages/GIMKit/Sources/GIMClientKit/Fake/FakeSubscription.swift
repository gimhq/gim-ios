import Foundation

/// Listener registration used by `FakeGimClient`. Delivery and `cancel()` share a lock, so no callback runs after
/// `cancel()` returns (a listener may cancel from inside its own callback).
final class FakeSubscription: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    func deliver(_ body: () -> Void) {
        lock.withLock {
            if !cancelled { body() }
        }
    }

    /// The handle returned to the caller; cancelling or releasing it ends this subscription.
    func taskHandle() -> TaskHandle {
        TaskHandle { [self] in cancel() }
    }
}

struct Subscriber<Listener: Sendable>: Sendable {
    let subscription: FakeSubscription
    let listener: Listener
}

extension Array {
    /// Drops cancelled subscribers and runs `body` for the remaining ones.
    mutating func deliver<Listener>(_ body: (Listener) -> Void) where Element == Subscriber<Listener> {
        removeAll { $0.subscription.isCancelled }
        for subscriber in self {
            subscriber.subscription.deliver { body(subscriber.listener) }
        }
    }
}
