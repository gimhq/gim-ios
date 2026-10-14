import Foundation

// Native mirror of the gim-core UniFFI records and enums. UniFFI maps ids to `String`.

public typealias UserId = String
public typealias DeviceId = String
public typealias ChatId = String
public typealias MessageId = String
public typealias MediaId = String

public struct Session: Sendable, Hashable, Codable {
    public var userId: UserId
    public var deviceId: DeviceId
    public var handle: String
    public var displayName: String
    public var serverUrl: String

    public init(userId: UserId, deviceId: DeviceId, handle: String, displayName: String, serverUrl: String) {
        self.userId = userId
        self.deviceId = deviceId
        self.handle = handle
        self.displayName = displayName
        self.serverUrl = serverUrl
    }
}

public enum LoginState: Sendable, Hashable, Codable {
    case unregistered
    case registered(Session)
}

public struct UserProfile: Sendable, Hashable, Codable {
    public var userId: UserId
    public var handle: String
    public var displayName: String
    public var avatarPath: String?

    public init(userId: UserId, handle: String, displayName: String, avatarPath: String? = nil) {
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.avatarPath = avatarPath
    }
}

public enum ChatKind: String, Sendable, Hashable, Codable {
    case direct
    case group
}

public struct ChatSummary: Sendable, Hashable, Codable {
    public var id: ChatId
    public var kind: ChatKind
    public var title: String
    public var avatarPath: String?
    public var lastMessagePreview: String?
    public var lastMessageSenderName: String?
    public var lastMessageAt: Date?
    public var unreadCount: UInt32
    public var memberCount: UInt32

    public init(
        id: ChatId,
        kind: ChatKind,
        title: String,
        avatarPath: String? = nil,
        lastMessagePreview: String? = nil,
        lastMessageSenderName: String? = nil,
        lastMessageAt: Date? = nil,
        unreadCount: UInt32 = 0,
        memberCount: UInt32
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.avatarPath = avatarPath
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageSenderName = lastMessageSenderName
        self.lastMessageAt = lastMessageAt
        self.unreadCount = unreadCount
        self.memberCount = memberCount
    }
}

public struct ChatMember: Sendable, Hashable, Codable {
    public var user: UserProfile
    public var isSelf: Bool

    public init(user: UserProfile, isSelf: Bool) {
        self.user = user
        self.isSelf = isSelf
    }
}

public struct ChatDetails: Sendable, Hashable, Codable {
    public var summary: ChatSummary
    public var members: [ChatMember]

    public init(summary: ChatSummary, members: [ChatMember]) {
        self.summary = summary
        self.members = members
    }
}

/// Media metadata. Paths point at files gim-core has already decrypted.
public struct MediaInfo: Sendable, Hashable, Codable {
    public var mediaId: MediaId
    public var mime: String
    public var size: UInt64
    public var fileName: String?
    public var width: UInt32?
    public var height: UInt32?
    public var thumbnailPath: String?

    public init(
        mediaId: MediaId,
        mime: String,
        size: UInt64,
        fileName: String? = nil,
        width: UInt32? = nil,
        height: UInt32? = nil,
        thumbnailPath: String? = nil
    ) {
        self.mediaId = mediaId
        self.mime = mime
        self.size = size
        self.fileName = fileName
        self.width = width
        self.height = height
        self.thumbnailPath = thumbnailPath
    }
}

public enum MediaKind: String, Sendable, Hashable, Codable {
    case image
    case file
}

public enum MessageContent: Sendable, Hashable, Codable {
    case text(String)
    case image(MediaInfo, caption: String?)
    case file(MediaInfo, caption: String?)
    case deleted
    case unsupported(String)
}

public enum SendState: Sendable, Hashable, Codable {
    case pending
    case sent
    case delivered
    case read
    case failed(reason: String)
}

public struct ReplyPreview: Sendable, Hashable, Codable {
    public var messageId: MessageId
    public var senderName: String
    public var preview: String

    public init(messageId: MessageId, senderName: String, preview: String) {
        self.messageId = messageId
        self.senderName = senderName
        self.preview = preview
    }
}

public struct ReactionGroup: Sendable, Hashable, Codable {
    public var emoji: String
    public var count: UInt32
    public var includesMe: Bool

    public init(emoji: String, count: UInt32, includesMe: Bool) {
        self.emoji = emoji
        self.count = count
        self.includesMe = includesMe
    }
}

public struct TimelineMessage: Sendable, Hashable, Codable, Identifiable {
    /// The outbox client id; stable from the optimistic insert onwards.
    public var id: MessageId
    public var chatId: ChatId
    public var senderId: UserId
    public var senderName: String
    public var isOwn: Bool
    public var timestamp: Date
    public var content: MessageContent
    public var replyTo: ReplyPreview?
    public var reactions: [ReactionGroup]
    public var editedAt: Date?
    /// Only set for own messages.
    public var sendState: SendState?

    public init(
        id: MessageId,
        chatId: ChatId,
        senderId: UserId,
        senderName: String,
        isOwn: Bool,
        timestamp: Date,
        content: MessageContent,
        replyTo: ReplyPreview? = nil,
        reactions: [ReactionGroup] = [],
        editedAt: Date? = nil,
        sendState: SendState? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.senderId = senderId
        self.senderName = senderName
        self.isOwn = isOwn
        self.timestamp = timestamp
        self.content = content
        self.replyTo = replyTo
        self.reactions = reactions
        self.editedAt = editedAt
        self.sendState = sendState
    }
}

/// Chat list change; the list is ordered by `lastMessageAt` descending.
public enum ChatListDiff: Sendable, Hashable {
    case reset([ChatSummary])
    case insert(index: UInt32, ChatSummary)
    case update(index: UInt32, ChatSummary)
    case remove(index: UInt32)
}

/// Timeline change; the timeline is ordered oldest first (index 0 = oldest loaded message).
public enum TimelineDiff: Sendable, Hashable {
    case reset([TimelineMessage])
    case insert(index: UInt32, TimelineMessage)
    case update(index: UInt32, TimelineMessage)
    case remove(index: UInt32)
}

public enum ConnectionState: String, Sendable, Hashable, Codable {
    case offline
    case connecting
    case online
}

public enum GimError: Error, Sendable, Hashable {
    case unauthorized
    case notFound
    case network(String)
    case invalidInput(String)
    case `internal`(String)
}
