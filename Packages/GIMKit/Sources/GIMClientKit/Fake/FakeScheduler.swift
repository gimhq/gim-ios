import Foundation

/// Decides when `FakeGimClient` runs delayed work (send status progression, peer typing and replies, reconnects).
public protocol FakeScheduler: Sendable {
    func schedule(after delay: Duration, _ action: @escaping @Sendable () async -> Void)
}

/// Runs actions after their real delay. Used by demo mode.
public struct RealDelayFakeScheduler: FakeScheduler {
    public init() {}

    public func schedule(after delay: Duration, _ action: @escaping @Sendable () async -> Void) {
        Task {
            try? await Task.sleep(for: delay)
            await action()
        }
    }
}

/// Runs actions as soon as possible, ignoring the delay. Order relative to the caller is not guaranteed.
public struct ImmediateFakeScheduler: FakeScheduler {
    public init() {}

    public func schedule(after delay: Duration, _ action: @escaping @Sendable () async -> Void) {
        Task { await action() }
    }
}

/// Queues actions on a virtual clock until a test advances it. Deterministic.
public final class ManualFakeScheduler: FakeScheduler, @unchecked Sendable {
    private struct Item {
        var due: Duration
        var sequence: Int
        var action: @Sendable () async -> Void
    }

    private let lock = NSLock()
    private var items: [Item] = []
    private var clock: Duration = .zero
    private var nextSequence = 0

    public init() {}

    /// Number of queued actions.
    public var pendingCount: Int {
        lock.withLock { items.count }
    }

    public func schedule(after delay: Duration, _ action: @escaping @Sendable () async -> Void) {
        lock.withLock {
            items.append(Item(due: clock + delay, sequence: nextSequence, action: action))
            nextSequence += 1
        }
    }

    /// Runs every action due within `duration` from the current virtual time, including actions they schedule.
    public func advance(by duration: Duration) async {
        let deadline = lock.withLock { clock + duration }
        while let item = popNext(notAfter: deadline) {
            await item.action()
        }
        lock.withLock { clock = max(clock, deadline) }
    }

    /// Runs queued actions in due order until the queue is empty.
    public func runUntilIdle() async {
        while let item = popNext(notAfter: nil) {
            await item.action()
        }
    }

    private func popNext(notAfter deadline: Duration?) -> Item? {
        lock.withLock {
            guard
                let index = items.indices.min(by: {
                    (items[$0].due, items[$0].sequence) < (items[$1].due, items[$1].sequence)
                })
            else { return nil }
            if let deadline, items[index].due > deadline { return nil }
            let item = items.remove(at: index)
            clock = max(clock, item.due)
            return item
        }
    }
}
