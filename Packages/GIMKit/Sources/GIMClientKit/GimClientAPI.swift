import Foundation

// Native mirror of gim-core's UniFFI `GimClient` object, `Timeline`, `LinkSession`, `PendingApproval`, `TaskHandle`,
// callback interfaces, platform hooks and `createClient` (`bindings/gim-ffi/src/`). Method names and argument labels match the generated
// `GIMCore.swift`; see docs/gim-core-mapping.md for the symbol table and the intentional differences.
//
// Callbacks may arrive on any thread (gim-core calls them from a Rust background thread). Hop to the main actor
// before touching UI state and keep their order.

/// Receives chat list changes, most recently updated chat first. The first callback is a `reset`.
public protocol ChatListListener: AnyObject, Sendable {
    func onUpdate(diffs: [ChatListDiff])
}

/// Receives timeline changes, oldest item first. The first callback is a `reset` with the loaded items.
public protocol TimelineListener: AnyObject, Sendable {
    func onUpdate(diffs: [TimelineDiff])
}

/// Receives connection state changes. The first callback carries the current state.
public protocol ConnectionStateListener: AnyObject, Sendable {
    func onChange(state: ConnectionState)
}

/// Receives the ids of the users currently typing in one chat (never the signed-in user). The first callback
/// carries the current set, possibly empty.
public protocol TypingListener: AnyObject, Sendable {
    func onUpdate(userIds: [String])
}

/// Services the app provides to gim-core, passed to `createClient`. Methods may be called from any thread.
public protocol PlatformHooks: AnyObject, Sendable {
    /// Reads a secret from the platform keystore; `nil` when the key does not exist. Throws when the keystore can't
    /// be read (e.g. locked before first unlock), so gim-core fails the call instead of treating the secret as absent.
    func secureStoreGet(key: String) throws -> Data?
    /// Writes a secret to the platform keystore, replacing any existing value.
    func secureStoreSet(key: String, value: Data) throws
    /// Deletes a secret; a missing key is not an error.
    func secureStoreDelete(key: String)
    /// Absolute path of an app-private directory, stable across launches.
    func dataDir() -> String
    /// Current network reachability. Changes are pushed with `GimClientAPI.setNetworkReachable(reachable:)`.
    func isNetworkReachable() -> Bool
}

/// Keeps a listener subscription alive. Releasing the last reference or calling `cancel()` ends the subscription;
/// no callback is delivered after `cancel()` returns. Calling `cancel()` twice is harmless.
public final class TaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?

    /// - Parameter onCancel: stops the subscription; runs once, on `cancel()` or when the handle is released.
    public init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    deinit {
        cancel()
    }

    public func cancel() {
        let action = lock.withLock {
            defer { onCancel = nil }
            return onCancel
        }
        action?()
    }

    /// Whether the subscription has ended.
    public func isFinished() -> Bool {
        lock.withLock { onCancel == nil }
    }
}

/// The message timeline of one chat.
public protocol Timeline: AnyObject, Sendable {
    func chatId() -> String
    /// Subscribes to timeline changes. The first callback is a `reset` with the currently loaded items.
    func addListener(listener: any TimelineListener) async -> TaskHandle
    /// Loads up to `count` older items (delivered through the listeners). Returns whether more history exists.
    func paginateBackwards(count: UInt16) async throws -> Bool
}

/// A link offer of a new device: show `qrString()` as a QR code, then pass it to `GimClientAPI.waitLink(link:)`.
/// Accepts a single bundle; start a new one after a failed `waitLink`.
public protocol LinkSession: AnyObject, Sendable {
    /// The string to encode in the QR code the old device scans.
    func qrString() -> String
}

/// A link approved on the old device: show `sas()`, then pass it to `GimClientAPI.confirmApproval(approval:accepted:)`.
public protocol PendingApproval: AnyObject, Sendable {
    /// The new device.
    func deviceId() -> String
    /// Six-digit short authentication string, `"123 456"`.
    func sas() -> String
}

/// One account on one device. Mirrors `GIMCore.GimClientProtocol`.
public protocol GimClientAPI: AnyObject, Sendable {
    /// The persisted session, or `nil` before an identity exists on this device (`createIdentity`,
    /// `restoreFromRecovery` or a device link).
    func session() async throws -> Session?
    /// The signed-in user's id; `nil` without a session. Synchronous.
    func userId() -> String?
    /// Whether opening this client discarded an existing local database (undecryptable or incompatible). The session
    /// is gone with it: show onboarding and tell the user that local history was lost. Synchronous.
    func localStateReset() -> Bool
    /// Stops sync and deletes the session, local data and keystore secrets. Create a new client afterwards.
    func signOut() async throws

    // Identity and devices (gim-core docs/API.md, "Identity and devices").

    /// Creates a new identity with this device as its first one and signs in. Returns the recovery code, which is
    /// stored nowhere and must be shown to the user once. `InvalidInput` with a session.
    func createIdentity(displayName: String) async throws -> String
    /// Restores the user on this fresh device from its recovery code: `InvalidInput` for a malformed code, `Crypto`
    /// for a wrong one, `NotFound` if the hub has no DeviceList of the user, `RetryLater` while the hub throttles.
    /// `revokeOthers` revokes every previously listed device. Chats are not rejoined automatically.
    func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws
    /// New device: starts a link; show `LinkSession.qrString()` and call `waitLink`. `hubs` are the hub URLs the old
    /// device may post the bundle to. Synchronous.
    func startLink(hubs: [String]) throws -> any LinkSession
    /// New device: waits (up to 10 minutes) for the old device to approve the link, then signs in as a new device of
    /// that user. Returns the SAS to compare with the old device's; finish with `confirmLink`.
    func waitLink(link: any LinkSession) async throws -> String
    /// New device: the user compared the SAS. `false` wipes the device like `signOut()`; create a new client
    /// afterwards.
    func confirmLink(accepted: Bool) async throws
    /// Old device: approves the link offer scanned from the new device's QR code and returns the pending approval
    /// carrying the SAS.
    func approveLink(qrString: String) async throws -> any PendingApproval
    /// Old device: the user compared the SAS. `true` adds the new device to every joined chat (the new device must
    /// have finished `waitLink`); `false` revokes it.
    func confirmApproval(approval: any PendingApproval, accepted: Bool) async throws
    /// The signed-in user's devices, including revoked ones.
    func devices() async throws -> [DeviceInfo]
    /// Another user's devices; empty for an unknown user.
    func userDevices(userId: String) async throws -> [DeviceInfo]
    /// Revokes another device of the signed-in user and removes it from every chat. `InvalidInput` for the current
    /// device.
    func revokeDevice(deviceId: String) async throws
    /// Synced to the user's other devices and announced to every joined chat. `InvalidInput` if empty.
    func setDisplayName(name: String) async throws
    /// Claims `handle` in the hub directory so others find the user with `findUser`; `Server(409)` if it is taken.
    func claimHandle(handle: String) async throws
    /// Releases the handle claimed with `claimHandle`; `InvalidInput` if there is none.
    func releaseHandle() async throws

    func startSync() async throws
    func stopSync() async throws
    /// Synchronous and never throws.
    func setNetworkReachable(reachable: Bool)

    /// `nil` if no such user exists.
    func findUser(handle: String) async throws -> UserProfile?
    /// Returns the existing direct chat with `userId` if there is one.
    func createDirectChat(userId: String) async throws -> String
    func createGroupChat(name: String, memberUserIds: [String]) async throws -> String
    /// Current members, one entry per user, including the signed-in user. There is no members listener: re-query
    /// when a `ChatListDiff` touches the chat or a `TimelineItem.membershipChange` arrives.
    func chatMembers(chatId: String) async throws -> [UserProfile]
    func addMembers(chatId: String, userIds: [String]) async throws
    func removeMember(chatId: String, userId: String) async throws
    func leaveChat(chatId: String) async throws
    /// `nil` leaves a field unchanged.
    func setGroupInfo(chatId: String, name: String?, avatarFilePath: String?) async throws

    /// Returns the message id; the message appears in the timeline immediately as `SendState.pending`.
    func sendText(chatId: String, body: String, replyTo: String?) async throws -> String
    /// The file is copied before the call returns.
    func sendMedia(
        chatId: String, filePath: String, mime: String, caption: String?, replyTo: String?
    ) async throws -> String
    func editMessage(chatId: String, messageId: String, newBody: String) async throws
    func deleteMessage(chatId: String, messageId: String) async throws
    func react(chatId: String, messageId: String, emoji: String) async throws
    func unreact(chatId: String, messageId: String, emoji: String) async throws
    /// For messages in `SendState.failed`.
    func retrySend(chatId: String, messageId: String) async throws
    /// Removes an unsent message from the outbox and the timeline.
    func cancelSend(chatId: String, messageId: String) async throws
    /// Marks everything up to and including `upToMessageId` as read and sends a read receipt.
    func markRead(chatId: String, upToMessageId: String) async throws
    func setTyping(chatId: String, active: Bool) async throws
    /// Tells the chat the user stopped typing; same as `setTyping(chatId:active: false)`. Does nothing unless typing
    /// was reported.
    func stopTyping(chatId: String) async throws

    /// Downloads and decrypts the attachment to `destPath`; returns the path of the decrypted file.
    func fetchMedia(chatId: String, messageId: String, destPath: String) async throws -> String
    /// Like `fetchMedia` for the thumbnail; `nil` if the media has none.
    func fetchThumbnail(chatId: String, messageId: String, destPath: String) async throws -> String?

    func chatList(listener: any ChatListListener) async throws -> TaskHandle
    func timeline(chatId: String) async throws -> any Timeline
    func connectionState(listener: any ConnectionStateListener) async throws -> TaskHandle
    func typing(chatId: String, listener: any TypingListener) async throws -> TaskHandle
}

/// Creates the client. Opens (or creates) local state under `hooks.dataDir()`; does not touch the network.
///
/// Until the gim-core bindings land this returns a demo `FakeGimClient` without a session that seeds the demo chats
/// when `createIdentity` is called.
public func createClient(config: ClientConfig, hooks: any PlatformHooks) async throws -> any GimClientAPI {
    try validateServerUrl(config.serverUrl)
    return FakeGimClient.demo(
        dataDirectory: hooks.dataDir(), registered: false, networkReachable: hooks.isNetworkReachable())
}

/// Same rules as gim-core: an `http` or `https` URL with a host.
private func validateServerUrl(_ value: String) throws {
    guard let components = URLComponents(string: value), let scheme = components.scheme else {
        throw GimError.InvalidInput(reason: "server_url: relative URL without a base")
    }
    guard ["http", "https"].contains(scheme.lowercased()) else {
        throw GimError.InvalidInput(reason: "server_url: unsupported scheme '\(scheme)'")
    }
    guard let host = components.host, !host.isEmpty else {
        throw GimError.InvalidInput(reason: "server_url: missing host")
    }
}

/// App-level factory, the single swap point between `createClient` and test or preview clients.
public protocol GimClientFactory: Sendable {
    func make(config: ClientConfig, hooks: any PlatformHooks) async throws -> any GimClientAPI
}

/// Creates clients with `createClient(config:hooks:)`.
public struct CoreGimClientFactory: GimClientFactory {
    public init() {}

    public func make(config: ClientConfig, hooks: any PlatformHooks) async throws -> any GimClientAPI {
        try await createClient(config: config, hooks: hooks)
    }
}
