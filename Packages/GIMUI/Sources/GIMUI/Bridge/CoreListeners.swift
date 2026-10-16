import Foundation
import GIMClientKit
import GIMCore

/// Hands gim-core callbacks, which arrive on gim-core's callback thread, to the main queue in arrival order, and
/// drops those still queued when the subscription is cancelled.
///
/// The adapters below only convert the values and return (gim-core docs/API.md, "Threading of platform callbacks").
/// Cancelling can happen on the callback thread too: when gim-core releases a listener there (after `signOut`), the
/// app listener's `AsyncStream` ends and cancels its `TaskHandle`. So the gim-core handle is cancelled and released
/// on the main queue, never synchronously inside a callback.
final class MainQueueRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var core: GIMCore.TaskHandle?

    func deliver(_ callback: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async { [self] in
            guard lock.withLock({ active }) else { return }
            callback()
        }
    }

    /// Drops the queued callbacks at once; cancels and releases the gim-core handle on the main queue.
    func stop() {
        // Unmanaged moves the only reference into the main-queue block, so the last release happens there.
        let core = lock.withLock { () -> Unmanaged<GIMCore.TaskHandle>? in
            active = false
            defer { self.core = nil }
            return self.core.map { Unmanaged.passRetained($0) }
        }
        guard let core else { return }
        DispatchQueue.main.async {
            core.takeRetainedValue().cancel()
        }
    }

    /// Wraps a gim-core subscription handle in a mirror `TaskHandle` that keeps it alive until cancelled.
    func handle(_ core: GIMCore.TaskHandle) -> GIMClientKit.TaskHandle {
        lock.withLock { self.core = core }
        return GIMClientKit.TaskHandle { [self] in stop() }
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

final class CoreHubListListener: GIMCore.HubListListener {
    private let listener: any GIMClientKit.HubListListener
    private let relay: MainQueueRelay

    init(_ listener: any GIMClientKit.HubListListener, relay: MainQueueRelay) {
        self.listener = listener
        self.relay = relay
    }

    func onUpdate(hubs: [GIMCore.HubInfo]) {
        let hubs = hubs.map { GIMClientKit.HubInfo($0) }
        relay.deliver { [listener] in listener.onUpdate(hubs: hubs) }
    }
}

/// Passes the app's `PlatformHooks` (Keychain, data directory, reachability) to gim-core. Called on gim-core's
/// callback thread, which waits for the answer: each method answers directly (a Keychain call, a constant, a locked
/// read) and never calls back into the client.
final class CorePlatformHooks: GIMCore.PlatformHooks {
    private let hooks: any GIMClientKit.PlatformHooks

    init(_ hooks: any GIMClientKit.PlatformHooks) {
        self.hooks = hooks
    }

    func secureStoreGet(key: String) throws -> Data? {
        try storageCall { try hooks.secureStoreGet(key: key) }
    }

    func secureStoreSet(key: String, value: Data) throws {
        try storageCall { try hooks.secureStoreSet(key: key, value: value) }
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

    /// Rethrows a keystore hook's errors as gim-core `GimError`s; anything else becomes `Storage`.
    private func storageCall<T>(_ call: () throws -> T) throws -> T {
        do {
            return try call()
        } catch let error as GIMClientKit.GimError {
            throw GIMCore.GimError(error)
        } catch {
            throw GIMCore.GimError.Storage(reason: String(describing: error))
        }
    }
}

/// Passes the app's `LocalTimeZone` to gim-core. Answers on gim-core's callback thread, without a hop: the zone only
/// reads Foundation's time zone data.
final class CoreLocalTimeZone: GIMCore.LocalTimeZone {
    private let zone: any GIMClientKit.LocalTimeZone

    init(_ zone: any GIMClientKit.LocalTimeZone) {
        self.zone = zone
    }

    func utcOffsetSecs(atMs: Int64) -> Int32 {
        zone.utcOffsetSecs(atMs: atMs)
    }
}
