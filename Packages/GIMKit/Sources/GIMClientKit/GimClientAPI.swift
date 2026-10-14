import Foundation

// Native mirror of gim-core's UniFFI `GimClient` object, its callback interfaces and platform hooks.

/// Receives chat list diffs. A new subscription first delivers a `reset` with the current list.
public protocol ChatListListener: AnyObject, Sendable {
    func onDiffs(_ diffs: [ChatListDiff])
}

/// Receives timeline diffs for one chat. A new subscription first delivers a `reset` with the loaded window.
public protocol TimelineListener: AnyObject, Sendable {
    func onDiffs(_ diffs: [TimelineDiff])
}

/// Receives connection state changes. A new subscription first delivers the current state.
public protocol ConnectionListener: AnyObject, Sendable {
    func onState(_ state: ConnectionState)
}

/// Receives the set of users currently typing in a chat. A new subscription first delivers the current set.
public protocol TypingListener: AnyObject, Sendable {
    func onTyping(chatId: ChatId, users: [UserProfile])
}

/// Keeps a listener registered until `cancel()` is called. No callbacks are delivered after `cancel()` returns.
public protocol SubscriptionHandle: AnyObject, Sendable {
    func cancel()
}

/// Secure key storage (Keychain on iOS) used by gim-core for the device identity secret.
public protocol SecureStorage: AnyObject, Sendable {
    func get(key: String) throws -> Data?
    func set(key: String, value: Data) throws
    func delete(key: String) throws
}

/// Native callbacks handed to gim-core at construction time.
public struct PlatformHooks: Sendable {
    public var secureStorage: any SecureStorage
    /// Absolute path of the app data directory owned by gim-core.
    public var dataDirectory: String

    public init(secureStorage: any SecureStorage, dataDirectory: String) {
        self.secureStorage = secureStorage
        self.dataDirectory = dataDirectory
    }
}

public protocol GimClientFactory: Sendable {
    func make(hooks: PlatformHooks) async throws -> any GimClientAPI
}

public protocol GimClientAPI: AnyObject, Sendable {
    func loginState() async throws -> LoginState
    func register(serverUrl: String, handle: String, displayName: String) async throws -> Session
    func logout() async throws

    func findUser(handle: String) async throws -> UserProfile?
    func createDirectChat(with user: UserId) async throws -> ChatId
    func createGroupChat(name: String, members: [UserId]) async throws -> ChatId
    func chatDetails(_ chatId: ChatId) async throws -> ChatDetails
    func addMember(_ chatId: ChatId, user: UserId) async throws
    func removeMember(_ chatId: ChatId, user: UserId) async throws

    func sendText(_ chatId: ChatId, text: String, replyTo: MessageId?) async throws -> MessageId
    func sendMedia(
        _ chatId: ChatId,
        filePath: String,
        mime: String,
        kind: MediaKind,
        caption: String?,
        replyTo: MessageId?,
        width: UInt32?,
        height: UInt32?
    ) async throws -> MessageId
    func edit(_ messageId: MessageId, text: String) async throws
    func delete(_ messageId: MessageId) async throws
    func react(_ messageId: MessageId, emoji: String, remove: Bool) async throws
    func retry(_ messageId: MessageId) async throws
    func markRead(_ chatId: ChatId) async throws
    func setTyping(_ chatId: ChatId, typing: Bool) async throws
    /// Loads up to `count` older messages into the timeline window. Returns whether more remain.
    func loadOlder(_ chatId: ChatId, count: UInt32) async throws -> Bool
    /// Returns the path of the decrypted media file, downloading it first if needed.
    func fetchMedia(_ mediaId: MediaId) async throws -> String
    /// Reachability pushed from the platform.
    func setNetworkAvailable(_ available: Bool) async

    func subscribeChatList(_ listener: any ChatListListener) async throws -> any SubscriptionHandle
    func subscribeTimeline(_ chatId: ChatId, _ listener: any TimelineListener) async throws -> any SubscriptionHandle
    func subscribeConnection(_ listener: any ConnectionListener) async throws -> any SubscriptionHandle
    func subscribeTyping(_ chatId: ChatId, _ listener: any TypingListener) async throws -> any SubscriptionHandle
}
