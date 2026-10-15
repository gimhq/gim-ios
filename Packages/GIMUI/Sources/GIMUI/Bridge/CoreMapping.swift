import Foundation
import GIMClientKit
import GIMCore

// One-to-one conversions between the generated `GIMCore` types and their GIMClientKit mirrors
// (docs/gim-core-mapping.md). Both modules declare the same names, so every type here is module-qualified.

/// Runs a gim-core call and rethrows its errors as the mirror `GimError`.
func bridged<T>(_ call: () async throws -> T) async throws -> T {
    do {
        return try await call()
    } catch let error as GIMCore.GimError {
        throw GIMClientKit.GimError(error)
    } catch let error as GIMClientKit.GimError {
        throw error
    } catch {
        throw GIMClientKit.GimError.Internal(reason: String(describing: error))
    }
}

extension GIMClientKit.GimError {
    init(_ core: GIMCore.GimError) {
        switch core {
        case .Network(let reason): self = .Network(reason: reason)
        case .NotRegistered: self = .NotRegistered
        case .InvalidInput(let reason): self = .InvalidInput(reason: reason)
        case .NotFound(let reason): self = .NotFound(reason: reason)
        case .Crypto(let reason): self = .Crypto(reason: reason)
        case .Storage(let reason): self = .Storage(reason: reason)
        case .Server(let status, let reason): self = .Server(status: status, reason: reason)
        case .Cancelled: self = .Cancelled
        case .NotImplemented: self = .NotImplemented
        case .Internal(let reason): self = .Internal(reason: reason)
        }
    }
}

extension GIMCore.GimError {
    /// For errors thrown by the platform hooks back into gim-core.
    init(_ mirror: GIMClientKit.GimError) {
        switch mirror {
        case .Network(let reason): self = .Network(reason: reason)
        case .NotRegistered: self = .NotRegistered
        case .InvalidInput(let reason): self = .InvalidInput(reason: reason)
        case .NotFound(let reason): self = .NotFound(reason: reason)
        case .Crypto(let reason): self = .Crypto(reason: reason)
        case .Storage(let reason): self = .Storage(reason: reason)
        case .Server(let status, let reason): self = .Server(status: status, reason: reason)
        case .Cancelled: self = .Cancelled
        case .NotImplemented: self = .NotImplemented
        case .Internal(let reason): self = .Internal(reason: reason)
        }
    }
}

extension GIMCore.ClientConfig {
    init(_ mirror: GIMClientKit.ClientConfig) {
        self.init(serverUrl: mirror.serverUrl)
    }
}

extension GIMClientKit.Session {
    init(_ core: GIMCore.Session) {
        self.init(userId: core.userId, deviceId: core.deviceId, handle: core.handle, displayName: core.displayName)
    }
}

extension GIMClientKit.UserProfile {
    init(_ core: GIMCore.UserProfile) {
        self.init(userId: core.userId, handle: core.handle, displayName: core.displayName)
    }
}

extension GIMClientKit.ChatKind {
    init(_ core: GIMCore.ChatKind) {
        switch core {
        case .direct: self = .direct
        case .group: self = .group
        }
    }
}

extension GIMClientKit.ChatSummary {
    init(_ core: GIMCore.ChatSummary) {
        self.init(
            chatId: core.chatId, kind: GIMClientKit.ChatKind(core.kind), name: core.name,
            avatar: core.avatar.map { GIMClientKit.MediaRef($0) },
            lastMessage: core.lastMessage.map { GIMClientKit.MessagePreview($0) }, unreadCount: core.unreadCount,
            updatedAtMs: core.updatedAtMs, memberCount: core.memberCount)
    }
}

extension GIMClientKit.MessagePreview {
    init(_ core: GIMCore.MessagePreview) {
        self.init(senderName: core.senderName, text: core.text, sentAtMs: core.sentAtMs, isOwn: core.isOwn)
    }
}

extension GIMClientKit.MediaRef {
    init(_ core: GIMCore.MediaRef) {
        self.init(
            chatId: core.chatId, messageId: core.messageId, mime: core.mime, size: core.size,
            hasThumbnail: core.hasThumbnail)
    }
}

extension GIMClientKit.TimelineItem {
    init(_ core: GIMCore.TimelineItem) {
        switch core {
        case .message(let item):
            self = .message(item: GIMClientKit.MessageItem(item))
        case .dateSeparator(let dayStartMs):
            self = .dateSeparator(dayStartMs: dayStartMs)
        case .membershipChange(let userName, let change, let atMs):
            self = .membershipChange(userName: userName, change: GIMClientKit.MembershipChangeKind(change), atMs: atMs)
        }
    }
}

extension GIMClientKit.MembershipChangeKind {
    init(_ core: GIMCore.MembershipChangeKind) {
        switch core {
        case .added: self = .added
        case .removed: self = .removed
        case .left: self = .left
        }
    }
}

extension GIMClientKit.MessageItem {
    init(_ core: GIMCore.MessageItem) {
        self.init(
            messageId: core.messageId, chatId: core.chatId, sender: GIMClientKit.UserProfile(core.sender),
            isOwn: core.isOwn, sentAtMs: core.sentAtMs, content: GIMClientKit.MessageContent(core.content),
            replyTo: core.replyTo.map { GIMClientKit.ReplyPreview($0) },
            reactions: core.reactions.map { GIMClientKit.ReactionGroup($0) }, edited: core.edited,
            sendState: core.sendState.map { GIMClientKit.SendState($0) })
    }
}

extension GIMClientKit.MessageContent {
    init(_ core: GIMCore.MessageContent) {
        switch core {
        case .text(let body):
            self = .text(body: body)
        case .image(let media, let width, let height, let caption):
            self = .image(media: GIMClientKit.MediaRef(media), width: width, height: height, caption: caption)
        case .file(let media, let fileName, let caption):
            self = .file(media: GIMClientKit.MediaRef(media), fileName: fileName, caption: caption)
        case .deleted:
            self = .deleted
        case .unsupported:
            self = .unsupported
        }
    }
}

extension GIMClientKit.ReplyPreview {
    init(_ core: GIMCore.ReplyPreview) {
        self.init(messageId: core.messageId, senderName: core.senderName, text: core.text)
    }
}

extension GIMClientKit.ReactionGroup {
    init(_ core: GIMCore.ReactionGroup) {
        self.init(emoji: core.emoji, count: core.count, own: core.own)
    }
}

extension GIMClientKit.SendState {
    init(_ core: GIMCore.SendState) {
        switch core {
        case .pending: self = .pending
        case .sent: self = .sent
        case .delivered: self = .delivered
        case .read: self = .read
        case .failed(let reason): self = .failed(reason: reason)
        }
    }
}

extension GIMClientKit.ConnectionState {
    init(_ core: GIMCore.ConnectionState) {
        switch core {
        case .offline: self = .offline
        case .connecting: self = .connecting
        case .connected: self = .connected
        case .syncing: self = .syncing
        }
    }
}

extension GIMClientKit.ChatListDiff {
    init(_ core: GIMCore.ChatListDiff) {
        switch core {
        case .append(let values): self = .append(values: values.map { GIMClientKit.ChatSummary($0) })
        case .clear: self = .clear
        case .pushFront(let value): self = .pushFront(value: GIMClientKit.ChatSummary(value))
        case .pushBack(let value): self = .pushBack(value: GIMClientKit.ChatSummary(value))
        case .popFront: self = .popFront
        case .popBack: self = .popBack
        case .insert(let index, let value): self = .insert(index: index, value: GIMClientKit.ChatSummary(value))
        case .set(let index, let value): self = .set(index: index, value: GIMClientKit.ChatSummary(value))
        case .remove(let index): self = .remove(index: index)
        case .truncate(let length): self = .truncate(length: length)
        case .reset(let values): self = .reset(values: values.map { GIMClientKit.ChatSummary($0) })
        }
    }
}

extension GIMClientKit.TimelineDiff {
    init(_ core: GIMCore.TimelineDiff) {
        switch core {
        case .append(let values): self = .append(values: values.map { GIMClientKit.TimelineItem($0) })
        case .clear: self = .clear
        case .pushFront(let value): self = .pushFront(value: GIMClientKit.TimelineItem(value))
        case .pushBack(let value): self = .pushBack(value: GIMClientKit.TimelineItem(value))
        case .popFront: self = .popFront
        case .popBack: self = .popBack
        case .insert(let index, let value): self = .insert(index: index, value: GIMClientKit.TimelineItem(value))
        case .set(let index, let value): self = .set(index: index, value: GIMClientKit.TimelineItem(value))
        case .remove(let index): self = .remove(index: index)
        case .truncate(let length): self = .truncate(length: length)
        case .reset(let values): self = .reset(values: values.map { GIMClientKit.TimelineItem($0) })
        }
    }
}
