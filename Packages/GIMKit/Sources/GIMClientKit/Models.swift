import Foundation

// Native mirror of the gim-core UniFFI records and enums (`bindings/gim-ffi/src/types.rs`, `client.rs`,
// `chat_list.rs`, `timeline.rs`, `error.rs`). Names, labels and field types match the generated `GIMCore.swift`;
// see docs/gim-core-mapping.md. Ids are opaque strings; timestamps are Unix epoch milliseconds.

public struct ClientConfig: Sendable, Hashable {
    /// Base URL of the hub, `http://` or `https://`.
    public var serverUrl: String

    public init(serverUrl: String) {
        self.serverUrl = serverUrl
    }
}

/// The signed-in account on this device.
public struct Session: Sendable, Hashable {
    public var userId: String
    public var deviceId: String
    /// Empty until `claimHandle`.
    public var handle: String
    public var displayName: String

    public init(userId: String, deviceId: String, handle: String, displayName: String) {
        self.userId = userId
        self.deviceId = deviceId
        self.handle = handle
        self.displayName = displayName
    }
}

/// Public profile of a user.
public struct UserProfile: Sendable, Hashable {
    public var userId: String
    public var handle: String
    public var displayName: String

    public init(userId: String, handle: String, displayName: String) {
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
    }
}

/// A device of a user, from the user's signed DeviceList.
public struct DeviceInfo: Sendable, Hashable {
    public var deviceId: String
    /// When the device was certified; 0 for revoked devices.
    public var createdAtMs: UInt64
    /// This client's device.
    public var isCurrent: Bool
    public var revoked: Bool

    public init(deviceId: String, createdAtMs: UInt64, isCurrent: Bool, revoked: Bool) {
        self.deviceId = deviceId
        self.createdAtMs = createdAtMs
        self.isCurrent = isCurrent
        self.revoked = revoked
    }
}

public enum ChatKind: Sendable, Hashable {
    case direct
    case group
}

/// One row of the chat list.
public struct ChatSummary: Sendable, Hashable {
    public var chatId: String
    public var kind: ChatKind
    /// Group name, or the other user's display name for a direct chat.
    public var name: String
    public var avatar: MediaRef?
    public var lastMessage: MessagePreview?
    public var unreadCount: UInt32
    public var updatedAtMs: UInt64
    public var memberCount: UInt32

    public init(
        chatId: String, kind: ChatKind, name: String, avatar: MediaRef?, lastMessage: MessagePreview?,
        unreadCount: UInt32, updatedAtMs: UInt64, memberCount: UInt32
    ) {
        self.chatId = chatId
        self.kind = kind
        self.name = name
        self.avatar = avatar
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.updatedAtMs = updatedAtMs
        self.memberCount = memberCount
    }
}

/// Last message shown in a chat list row.
public struct MessagePreview: Sendable, Hashable {
    public var senderName: String
    /// Plain-text rendering ("Photo", "File: report.pdf" for media).
    public var text: String
    public var sentAtMs: UInt64
    public var isOwn: Bool

    public init(senderName: String, text: String, sentAtMs: UInt64, isOwn: Bool) {
        self.senderName = senderName
        self.text = text
        self.sentAtMs = sentAtMs
        self.isOwn = isOwn
    }
}

/// One row of a chat timeline.
public enum TimelineItem: Sendable, Hashable {
    case message(item: MessageItem)
    /// Inserted before the first item of each local calendar day.
    case dateSeparator(dayStartMs: UInt64)
    case membershipChange(userName: String, change: MembershipChangeKind, atMs: UInt64)
}

public enum MembershipChangeKind: Sendable, Hashable {
    case added
    case removed
    case left
}

public struct MessageItem: Sendable, Hashable {
    /// Client id of the message; stable from local echo to delivery.
    public var messageId: String
    public var chatId: String
    public var sender: UserProfile
    public var isOwn: Bool
    public var sentAtMs: UInt64
    public var content: MessageContent
    public var replyTo: ReplyPreview?
    public var reactions: [ReactionGroup]
    public var edited: Bool
    /// Delivery state of own messages; `nil` for messages from others.
    public var sendState: SendState?

    public init(
        messageId: String, chatId: String, sender: UserProfile, isOwn: Bool, sentAtMs: UInt64,
        content: MessageContent, replyTo: ReplyPreview?, reactions: [ReactionGroup], edited: Bool,
        sendState: SendState?
    ) {
        self.messageId = messageId
        self.chatId = chatId
        self.sender = sender
        self.isOwn = isOwn
        self.sentAtMs = sentAtMs
        self.content = content
        self.replyTo = replyTo
        self.reactions = reactions
        self.edited = edited
        self.sendState = sendState
    }
}

public enum MessageContent: Sendable, Hashable {
    case text(body: String)
    case image(media: MediaRef, width: UInt32?, height: UInt32?, caption: String?)
    case file(media: MediaRef, fileName: String?, caption: String?)
    /// The sender deleted the message.
    case deleted
    /// Content this client version cannot render.
    case unsupported
}

/// Handle to an encrypted attachment. Pass its ids to `fetchMedia` / `fetchThumbnail`; keys and blob ids never
/// leave gim-core.
public struct MediaRef: Sendable, Hashable {
    public var chatId: String
    public var messageId: String
    public var mime: String
    public var size: UInt64
    public var hasThumbnail: Bool

    public init(chatId: String, messageId: String, mime: String, size: UInt64, hasThumbnail: Bool) {
        self.chatId = chatId
        self.messageId = messageId
        self.mime = mime
        self.size = size
        self.hasThumbnail = hasThumbnail
    }
}

/// Quoted message shown above a reply.
public struct ReplyPreview: Sendable, Hashable {
    public var messageId: String
    public var senderName: String
    public var text: String

    public init(messageId: String, senderName: String, text: String) {
        self.messageId = messageId
        self.senderName = senderName
        self.text = text
    }
}

public struct ReactionGroup: Sendable, Hashable {
    public var emoji: String
    public var count: UInt32
    /// Whether the signed-in user is among the reactors.
    public var own: Bool

    public init(emoji: String, count: UInt32, own: Bool) {
        self.emoji = emoji
        self.count = count
        self.own = own
    }
}

public enum SendState: Sendable, Hashable {
    /// Queued in the outbox or being uploaded.
    case pending
    /// Accepted by the server.
    case sent
    /// Delivered to at least one recipient device.
    case delivered
    /// Read by at least one recipient.
    case read
    /// Gave up; `retrySend` or `cancelSend`.
    case failed(reason: String)
}

public enum ConnectionState: Sendable, Hashable {
    case offline
    case connecting
    case connected
    /// Connected and catching up on missed events.
    case syncing
}

/// Incremental change to the chat list, mirroring eyeball-im `VectorDiff`. Apply the diffs of one `onUpdate` call
/// in order; indices refer to the list as it is after the previous diff of the batch.
public enum ChatListDiff: Sendable, Hashable {
    case append(values: [ChatSummary])
    case clear
    case pushFront(value: ChatSummary)
    case pushBack(value: ChatSummary)
    case popFront
    case popBack
    case insert(index: UInt32, value: ChatSummary)
    case set(index: UInt32, value: ChatSummary)
    case remove(index: UInt32)
    case truncate(length: UInt32)
    case reset(values: [ChatSummary])
}

/// Incremental change to a timeline, mirroring eyeball-im `VectorDiff`. Same rules as `ChatListDiff`.
public enum TimelineDiff: Sendable, Hashable {
    case append(values: [TimelineItem])
    case clear
    case pushFront(value: TimelineItem)
    case pushBack(value: TimelineItem)
    case popFront
    case popBack
    case insert(index: UInt32, value: TimelineItem)
    case set(index: UInt32, value: TimelineItem)
    case remove(index: UInt32)
    case truncate(length: UInt32)
    case reset(values: [TimelineItem])
}

/// Error returned by every fallible gim-core call. Case names keep the generated UpperCamelCase spelling.
// swift-format-ignore: AlwaysUseLowerCamelCase
public enum GimError: Error, Sendable, Hashable, LocalizedError {
    /// The server could not be reached or the connection broke.
    case Network(reason: String)
    /// The call needs a session: create an identity, restore one or link this device first. Also returned after
    /// `signOut` and once the hub reports this device as revoked.
    case NotRegistered
    /// An argument was rejected before anything was sent.
    case InvalidInput(reason: String)
    /// The chat, message, user or media does not exist locally or on the server.
    case NotFound(reason: String)
    /// MLS or media encryption/decryption failed.
    case Crypto(reason: String)
    /// The local database or file system failed.
    case Storage(reason: String)
    /// The hub answered with a non-success HTTP status.
    case Server(status: UInt16, reason: String)
    /// The hub is throttling the call (HTTP 429) or a remote hub is unavailable (HTTP 503) and gim-core's bounded
    /// retries are used up; try again after `retryAfterSecs`.
    case RetryLater(status: UInt16, retryAfterSecs: UInt64, reason: String)
    /// The operation was cancelled (sign-out, `stopSync`, `cancelSend`).
    case Cancelled
    /// The call is part of the API contract but not implemented yet.
    case NotImplemented
    /// A bug or an unexpected failure inside gim-core or a platform callback.
    case Internal(reason: String)

    public var errorDescription: String? {
        String(reflecting: self)
    }
}
