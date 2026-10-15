import Foundation
import GIMClientKit
import Network

/// Forwards network path changes to `GimClientAPI.setNetworkAvailable`, in order and without repeats.
public final class ReachabilityMonitor: Sendable {
    private let monitor = NWPathMonitor()
    private let continuation: AsyncStream<Bool>.Continuation
    private let forwarding: Task<Void, Never>

    public init(client: any GimClientAPI) {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        self.continuation = continuation
        forwarding = Task {
            var last: Bool?
            for await available in stream where available != last {
                last = available
                await client.setNetworkAvailable(available)
            }
        }
    }

    public func start() {
        monitor.pathUpdateHandler = { [continuation] path in
            continuation.yield(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "im.g.apps.reachability"))
    }

    public func stop() {
        monitor.cancel()
        continuation.finish()
    }

    deinit {
        stop()
        forwarding.cancel()
    }
}
