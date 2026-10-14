import Foundation

// Native mirror of gim-core's UniFFI `GimClient` object, `Timeline`, `TaskHandle`, callback interfaces, platform
// hooks and `createClient` (`bindings/gim-ffi/src/`). Method names and argument labels match the generated
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
    /// Reads a secret from the platform keystore; `nil` when the key does not exist.
    func secureStoreGet(key: String) -> Data?
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

/// One account on one device. Mirrors `GIMCore.GimClientProtocol`.
public protocol GimClientAPI: AnyObject, Sendable {
    /// The persisted session, or `nil` before `register`.
    func session() async throws -> Session?
    func register(handle: String, displayName: String) async throws -> Session
    /// Stops sync and deletes the session, local data and keystore secrets. Create a new client afterwards.
    func signOut() async throws

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
/// Until the gim-core bindings land this returns an unregistered demo `FakeGimClient` that seeds the demo chats
/// when `register` is called.
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
