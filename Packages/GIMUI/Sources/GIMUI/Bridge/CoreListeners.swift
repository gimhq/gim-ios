import Foundation
import GIMClientKit
import GIMCore

/// Hands gim-core callbacks, which arrive on a Rust background thread, to the main queue in arrival order, and
/// drops those still queued when the subscription is cancelled.
final class MainQueueRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    func deliver(_ callback: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async { [self] in
            guard lock.withLock({ active }) else { return }
            callback()
        }
    }

    func stop() {
        lock.withLock { active = false }
    }

    /// Wraps a gim-core subscription handle in a mirror `TaskHandle` that keeps it alive until cancelled.
    func handle(_ core: GIMCore.TaskHandle) -> GIMClientKit.TaskHandle {
        GIMClientKit.TaskHandle { [self] in
            stop()
            core.cancel()
        }
    }
}

final class CoreChatListListener: GIMCore.ChatListListener {
    private let listener: any GIMClientKit.ChatListListener
    private let relay: MainQueueRelay

    init(_ listener: any GIMClientKit.ChatListListener, relay: MainQueueRelay) {
        self.listener = listener
        self.relay = relay
    }

    func onUpdate(diffs: [GIMCore.ChatListDiff]) {
        let diffs = diffs.map { GIMClientKit.ChatListDiff($0) }
        relay.deliver { [listener] in listener.onUpdate(diffs: diffs) }
    }
}

final class CoreTimelineListener: GIMCore.TimelineListener {
    private let listener: any GIMClientKit.TimelineListener
    private let relay: MainQueueRelay

    init(_ listener: any GIMClientKit.TimelineListener, relay: MainQueueRelay) {
        self.listener = listener
        self.relay = relay
    }

    func onUpdate(diffs: [GIMCore.TimelineDiff]) {
        let diffs = diffs.map { GIMClientKit.TimelineDiff($0) }
        relay.deliver { [listener] in listener.onUpdate(diffs: diffs) }
    }
}

final class CoreConnectionStateListener: GIMCore.ConnectionStateListener {
    private let listener: any GIMClientKit.ConnectionStateListener
    private let relay: MainQueueRelay

    init(_ listener: any GIMClientKit.ConnectionStateListener, relay: MainQueueRelay) {
        self.listener = listener
        self.relay = relay
    }

    func onChange(state: GIMCore.ConnectionState) {
        let state = GIMClientKit.ConnectionState(state)
        relay.deliver { [listener] in listener.onChange(state: state) }
    }
}

final class CoreTypingListener: GIMCore.TypingListener {
    private let listener: any GIMClientKit.TypingListener
    private let relay: MainQueueRelay

    init(_ listener: any GIMClientKit.TypingListener, relay: MainQueueRelay) {
        self.listener = listener
        self.relay = relay
    }

    func onUpdate(userIds: [String]) {
        relay.deliver { [listener] in listener.onUpdate(userIds: userIds) }
    }
}

/// Passes the app's `PlatformHooks` (Keychain, data directory, reachability) to gim-core.
final class CorePlatformHooks: GIMCore.PlatformHooks {
    private let hooks: any GIMClientKit.PlatformHooks

    init(_ hooks: any GIMClientKit.PlatformHooks) {
        self.hooks = hooks
    }

    func secureStoreGet(key: String) -> Data? {
        hooks.secureStoreGet(key: key)
    }

    func secureStoreSet(key: String, value: Data) throws {
        do {
            try hooks.secureStoreSet(key: key, value: value)
        } catch let error as GIMClientKit.GimError {
            throw GIMCore.GimError(error)
        } catch {
            throw GIMCore.GimError.Storage(reason: String(describing: error))
        }
    }

    func secureStoreDelete(key: String) {
        hooks.secureStoreDelete(key: key)
    }

    func dataDir() -> String {
        hooks.dataDir()
    }

    func isNetworkReachable() -> Bool {
        hooks.isNetworkReachable()
    }
}
