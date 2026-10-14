import Foundation
import GIMClientKit
import Network

/// Tracks network reachability for `PlatformHooks.isNetworkReachable()` and forwards changes to the attached
/// client's `setNetworkReachable(reachable:)`, in order and without repeats.
public final class ReachabilityMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var reachable = true
    private weak var client: (any GimClientAPI)?

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(path.status == .satisfied)
        }
        // A serial queue keeps the updates in order.
        monitor.start(queue: DispatchQueue(label: "im.g.apps.reachability"))
    }

    deinit {
        monitor.cancel()
    }

    public var isReachable: Bool {
        lock.withLock { reachable }
    }

    /// The client that receives reachability changes; `nil` detaches.
    public func attach(_ client: (any GimClientAPI)?) {
        lock.withLock { self.client = client }
    }

    private func update(_ value: Bool) {
        let target: (any GimClientAPI)? = lock.withLock {
            guard value != reachable else { return nil }
            reachable = value
            return client
        }
        target?.setNetworkReachable(reachable: value)
    }
}
