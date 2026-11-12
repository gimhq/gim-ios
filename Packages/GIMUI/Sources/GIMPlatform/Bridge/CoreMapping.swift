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

/// Synchronous `bridged`.
func bridgedSync<T>(_ call: () throws -> T) throws -> T {
    do {
        return try call()
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
        case .RetryLater(let status, let retryAfterSecs, let reason):
            self = .RetryLater(status: status, retryAfterSecs: retryAfterSecs, reason: reason)
        case .Cancelled: self = .Cancelled
        case .NotImplemented: self = .NotImplemented
        case .Internal(let reason): self = .Internal(reason: reason)
        case .ChatNotActive(let chatId, let state):
            self = .ChatNotActive(chatId: chatId, state: GIMClientKit.ChatState(state))
        case .HubNotVerified(let reason): self = .HubNotVerified(reason: reason)
        case .HubOwnsGroups(let hubId, let groupCount): self = .HubOwnsGroups(hubId: hubId, groupCount: groupCount)
        case .LastHub(let hubId): self = .LastHub(hubId: hubId)
        case .HomeHub(let hubId): self = .HomeHub(hubId: hubId)
        case .HubNotDrained(let hubId, let reason): self = .HubNotDrained(hubId: hubId, reason: reason)
        case .UserSuspended(let hubId): self = .UserSuspended(hubId: hubId)
        case .UserNotAdmitted(let hubId): self = .UserNotAdmitted(hubId: hubId)
        case .NotAdmittedByPeer(let hubId, let chatId): self = .NotAdmittedByPeer(hubId: hubId, chatId: chatId)
        case .ContactNotAdmitted(let userIds): self = .ContactNotAdmitted(userIds: userIds)
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
        case .RetryLater(let status, let retryAfterSecs, let reason):
            self = .RetryLater(status: status, retryAfterSecs: retryAfterSecs, reason: reason)
        case .Cancelled: self = .Cancelled
        case .NotImplemented: self = .NotImplemented
        case .Internal(let reason): self = .Internal(reason: reason)
        case .ChatNotActive(let chatId, let state):
            self = .ChatNotActive(chatId: chatId, state: GIMCore.ChatState(state))
        case .HubNotVerified(let reason): self = .HubNotVerified(reason: reason)
        case .HubOwnsGroups(let hubId, let groupCount): self = .HubOwnsGroups(hubId: hubId, groupCount: groupCount)
        case .LastHub(let hubId): self = .LastHub(hubId: hubId)
        case .HomeHub(let hubId): self = .HomeHub(hubId: hubId)
        case .HubNotDrained(let hubId, let reason): self = .HubNotDrained(hubId: hubId, reason: reason)
        case .UserSuspended(let hubId): self = .UserSuspended(hubId: hubId)
        case .UserNotAdmitted(let hubId): self = .UserNotAdmitted(hubId: hubId)
        case .NotAdmittedByPeer(let hubId, let chatId): self = .NotAdmittedByPeer(hubId: hubId, chatId: chatId)
        case .ContactNotAdmitted(let userIds): self = .ContactNotAdmitted(userIds: userIds)
        }
    }
}

extension GIMClientKit.ChatState {
    init(_ core: GIMCore.ChatState) {
        switch core {
        case .active: self = .active
        case .leaving: self = .leaving
        case .left: self = .left
        }
    }
}

extension GIMCore.ChatState {
    init(_ mirror: GIMClientKit.ChatState) {
        switch mirror {
        case .active: self = .active
        case .leaving: self = .leaving
        case .left: self = .left
        }
    }
}

extension GIMCore.ClientConfig {
    init(_ mirror: GIMClientKit.ClientConfig) {
        self.init(
            serverUrl: mirror.serverUrl, mode: mirror.mode.map { GIMCore.ClientMode($0) },
            keepServerUrl: mirror.keepServerUrl)
    }
}

extension GIMCore.ClientMode {
    init(_ mirror: GIMClientKit.ClientMode) {
        switch mirror {
        case .app: self = .app
        case .`extension`: self = .`extension`
        }
    }
}

extension GIMCore.PushRegistration {
    init(_ mirror: GIMClientKit.PushRegistration) {
        self.init(
            provider: mirror.provider, token: mirror.token, appId: mirror.appId, sandbox: mirror.sandbox,
            p256dh: mirror.p256dh, auth: mirror.auth)
    }
}

extension GIMClientKit.NotificationKind {
    init(_ core: GIMCore.NotificationKind) {
        switch core {
        case .message: self = .message
        case .reaction: self = .reaction
        case .invite: self = .invite
        case .membership: self = .membership
        case .generic: self = .generic
        }
    }
}

extension GIMClientKit.NotificationContent {
    init(_ core: GIMCore.NotificationContent) {
        self.init(
            chatId: core.chatId, chatTitle: core.chatTitle, senderUserId: core.senderUserId,
            senderDisplayName: core.senderDisplayName, body: core.body, messageId: core.messageId,
            collapseId: core.collapseId, kind: GIMClientKit.NotificationKind(core.kind),
            shouldDisplay: core.shouldDisplay, timestamp: core.timestamp)
    }
}

extension GIMClientKit.Session {
    init(_ core: GIMCore.Session) {
        self.init(userId: core.userId, deviceId: core.deviceId, displayName: core.displayName)
    }
}

extension GIMClientKit.DeviceInfo {
    init(_ core: GIMCore.DeviceInfo) {
        self.init(
            deviceId: core.deviceId, createdAtMs: core.createdAtMs, isCurrent: core.isCurrent, revoked: core.revoked)
    }
}

extension GIMClientKit.HubState {
    init(_ core: GIMCore.HubState) {
        switch core {
        case .unverified: self = .unverified
        case .verified: self = .verified
        case .removed: self = .removed
        }
    }
}

extension GIMClientKit.HubInfo {
    init(_ core: GIMCore.HubInfo) {
        self.init(
            hubId: core.hubId, url: core.url, state: GIMClientKit.HubState(core.state), priority: core.priority,
            isPrimary: core.isPrimary, isHome: core.isHome, signedIn: core.signedIn)
    }
}

extension GIMClientKit.UserProfile {
    init(_ core: GIMCore.UserProfile) {
        self.init(userId: core.userId, displayName: core.displayName, hasAvatar: core.hasAvatar)
    }
}

extension GIMClientKit.PrivacySettings {
    init(_ core: GIMCore.PrivacySettings) {
        self.init(
            readReceipts: core.readReceipts, typingIndicators: core.typingIndicators,
            blockedUserIds: core.blockedUserIds)
    }
}

extension GIMClientKit.RecoveryRotation {
    init(_ core: GIMCore.RecoveryRotation) {
        self.init(recoveryCode: core.recoveryCode, unsyncedHubIds: core.unsyncedHubIds)
    }
}

extension GIMCore.ReportReason {
    init(_ mirror: GIMClientKit.ReportReason) {
        switch mirror {
        case .spam: self = .spam
        case .harassment: self = .harassment
        case .inappropriate: self = .inappropriate
        case .scam: self = .scam
        case .other: self = .other
        }
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
            updatedAtMs: core.updatedAtMs, memberCount: core.memberCount, state: GIMClientKit.ChatState(core.state),
            peer: core.peer.map { GIMClientKit.UserProfile($0) }, isNoteToSelf: core.isNoteToSelf,
            mutedUntilMs: core.mutedUntilMs, pinned: core.pinned, archived: core.archived, blocked: core.blocked)
    }
}

extension GIMClientKit.MessagePreview {
    init(_ core: GIMCore.MessagePreview) {
        self.init(
            senderName: core.senderName, text: core.text, sentAtMs: core.sentAtMs, isOwn: core.isOwn,
            sendState: core.sendState.map { GIMClientKit.SendState($0) })
    }
}

extension GIMCore.RecoveryKitLabels {
    init(_ mirror: GIMClientKit.RecoveryKitLabels) {
        self.init(title: mirror.title, accountId: mirror.accountId, recoveryKey: mirror.recoveryKey, note: mirror.note)
    }
}

extension GIMClientKit.ParsedRecoveryKit {
    init(_ core: GIMCore.ParsedRecoveryKit) {
        self.init(userId: core.userId, recoveryCode: core.recoveryCode)
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
        case .membershipChange(let userName, let change, let atMs, let userId, let actorUserId):
            self = .membershipChange(
                userName: userName, change: GIMClientKit.MembershipChangeKind(change), atMs: atMs, userId: userId,
                actorUserId: actorUserId)
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
        case .failed(let reason, let cause): self = .failed(reason: reason, cause: GIMClientKit.SendFailure(cause))
        }
    }
}

extension GIMClientKit.SendFailure {
    init(_ core: GIMCore.SendFailure) {
        switch core {
        case .userSuspended: self = .userSuspended
        case .userNotAdmitted: self = .userNotAdmitted
        case .notAdmittedByPeer: self = .notAdmittedByPeer
        case .rejected: self = .rejected
        case .other: self = .other
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
