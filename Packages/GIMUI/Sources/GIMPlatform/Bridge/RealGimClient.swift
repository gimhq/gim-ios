import Foundation
import GIMClientKit
import GIMCore

/// Creates clients backed by gim-core (`GIMCore.createClient`).
public struct RealGimClientFactory: GimClientFactory {
    public init() {}

    public func make(
        config: GIMClientKit.ClientConfig, hooks: any GIMClientKit.PlatformHooks
    ) async throws -> any GimClientAPI {
        let core = try await bridged {
            try await GIMCore.createClient(config: GIMCore.ClientConfig(config), hooks: CorePlatformHooks(hooks))
        }
        return RealGimClient(core)
    }
}

/// Adapts gim-core's generated `GimClient` to `GimClientAPI`: converts every value 1:1, rethrows `GimError`s as
/// the mirror type and delivers listener callbacks on the main queue.
public final class RealGimClient: GimClientAPI {
    private let core: GIMCore.GimClient

    init(_ core: GIMCore.GimClient) {
        self.core = core
    }

    public func session() async throws -> GIMClientKit.Session? {
        try await bridged { try await core.session().map { GIMClientKit.Session($0) } }
    }

    public func userId() -> String? {
        core.userId()
    }

    public func localStateReset() -> Bool {
        core.localStateReset()
    }

    public func recoveryCode() throws -> String? {
        try bridgedSync { try core.recoveryCode() }
    }

    public func signOut() async throws {
        try await bridged { try await core.signOut() }
    }

    public func createIdentity(displayName: String) async throws -> String {
        try await bridged { try await core.createIdentity(displayName: displayName) }
    }

    public func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws {
        try await bridged {
            try await core.restoreFromRecovery(userId: userId, recoveryCode: recoveryCode, revokeOthers: revokeOthers)
        }
    }

    public func startLink(hubs: [String]) throws -> any GIMClientKit.LinkSession {
        try bridgedSync { try RealLinkSession(core.startLink(hubs: hubs)) }
    }

    public func waitLink(link: any GIMClientKit.LinkSession) async throws -> String {
        guard let link = link as? RealLinkSession else {
            throw GIMClientKit.GimError.InvalidInput(reason: "link was not started by this client")
        }
        return try await bridged { try await core.waitLink(link: link.core) }
    }

    public func confirmLink(accepted: Bool) async throws {
        try await bridged { try await core.confirmLink(accepted: accepted) }
    }

    public func approveLink(qrString: String) async throws -> any GIMClientKit.PendingApproval {
        try await bridged { try await RealPendingApproval(core.approveLink(qrString: qrString)) }
    }

    public func confirmApproval(approval: any GIMClientKit.PendingApproval, accepted: Bool) async throws {
        guard let approval = approval as? RealPendingApproval else {
            throw GIMClientKit.GimError.InvalidInput(reason: "approval was not created by this client")
        }
        try await bridged { try await core.confirmApproval(approval: approval.core, accepted: accepted) }
    }

    public func devices() async throws -> [GIMClientKit.DeviceInfo] {
        try await bridged { try await core.devices().map { GIMClientKit.DeviceInfo($0) } }
    }

    public func userDevices(userId: String) async throws -> [GIMClientKit.DeviceInfo] {
        try await bridged { try await core.userDevices(userId: userId).map { GIMClientKit.DeviceInfo($0) } }
    }

    public func revokeDevice(deviceId: String) async throws {
        try await bridged { try await core.revokeDevice(deviceId: deviceId) }
    }

    public func setDisplayName(name: String) async throws {
        try await bridged { try await core.setDisplayName(name: name) }
    }

    public func startSync() async throws {
        try await bridged { try await core.startSync() }
    }

    public func stopSync() async throws {
        try await bridged { try await core.stopSync() }
    }

    public func setNetworkReachable(reachable: Bool) {
        core.setNetworkReachable(reachable: reachable)
    }

    public func createDirectChat(userId: String) async throws -> String {
        try await bridged { try await core.createDirectChat(userId: userId) }
    }

    public func createGroupChat(name: String, memberUserIds: [String]) async throws -> String {
        try await bridged { try await core.createGroupChat(name: name, memberUserIds: memberUserIds) }
    }

    public func chatMembers(chatId: String) async throws -> [GIMClientKit.UserProfile] {
        try await bridged { try await core.chatMembers(chatId: chatId).map { GIMClientKit.UserProfile($0) } }
    }

    public func addMembers(chatId: String, userIds: [String]) async throws {
        try await bridged { try await core.addMembers(chatId: chatId, userIds: userIds) }
    }

    public func removeMember(chatId: String, userId: String) async throws {
        try await bridged { try await core.removeMember(chatId: chatId, userId: userId) }
    }

    public func leaveChat(chatId: String) async throws {
        try await bridged { try await core.leaveChat(chatId: chatId) }
    }

    public func chatState(chatId: String) async throws -> GIMClientKit.ChatState {
        try await bridged { GIMClientKit.ChatState(try await core.chatState(chatId: chatId)) }
    }

    public func setGroupInfo(chatId: String, name: String?, avatarFilePath: String?) async throws {
        try await bridged { try await core.setGroupInfo(chatId: chatId, name: name, avatarFilePath: avatarFilePath) }
    }

    public func sendText(chatId: String, body: String, replyTo: String?) async throws -> String {
        try await bridged { try await core.sendText(chatId: chatId, body: body, replyTo: replyTo) }
    }

    public func sendMedia(
        chatId: String, filePath: String, mime: String, caption: String?, replyTo: String?
    ) async throws -> String {
        try await bridged {
            try await core.sendMedia(chatId: chatId, filePath: filePath, mime: mime, caption: caption, replyTo: replyTo)
        }
    }

    public func editMessage(chatId: String, messageId: String, newBody: String) async throws {
        try await bridged { try await core.editMessage(chatId: chatId, messageId: messageId, newBody: newBody) }
    }

    public func deleteMessage(chatId: String, messageId: String) async throws {
        try await bridged { try await core.deleteMessage(chatId: chatId, messageId: messageId) }
    }

    public func react(chatId: String, messageId: String, emoji: String) async throws {
        try await bridged { try await core.react(chatId: chatId, messageId: messageId, emoji: emoji) }
    }

    public func unreact(chatId: String, messageId: String, emoji: String) async throws {
        try await bridged { try await core.unreact(chatId: chatId, messageId: messageId, emoji: emoji) }
    }

    public func retrySend(chatId: String, messageId: String) async throws {
        try await bridged { try await core.retrySend(chatId: chatId, messageId: messageId) }
    }

    public func cancelSend(chatId: String, messageId: String) async throws {
        try await bridged { try await core.cancelSend(chatId: chatId, messageId: messageId) }
    }

    public func markRead(chatId: String, upToMessageId: String) async throws {
        try await bridged { try await core.markRead(chatId: chatId, upToMessageId: upToMessageId) }
    }

    public func setTyping(chatId: String, active: Bool) async throws {
        try await bridged { try await core.setTyping(chatId: chatId, active: active) }
    }

    public func stopTyping(chatId: String) async throws {
        try await bridged { try await core.stopTyping(chatId: chatId) }
    }

    public func fetchMedia(chatId: String, messageId: String, destPath: String) async throws -> String {
        try await bridged { try await core.fetchMedia(chatId: chatId, messageId: messageId, destPath: destPath) }
    }

    public func fetchThumbnail(chatId: String, messageId: String, destPath: String) async throws -> String? {
        try await bridged { try await core.fetchThumbnail(chatId: chatId, messageId: messageId, destPath: destPath) }
    }

    public func chatList(listener: any GIMClientKit.ChatListListener) async throws -> GIMClientKit.TaskHandle {
        let relay = MainQueueRelay()
        let handle = try await bridged {
            try await core.chatList(listener: CoreChatListListener(listener, relay: relay))
        }
        return relay.handle(handle)
    }

    public func timeline(chatId: String) async throws -> any GIMClientKit.Timeline {
        try await bridged { try await RealTimeline(core.timeline(chatId: chatId)) }
    }

    public func setLocalTimeZone(zone: (any GIMClientKit.LocalTimeZone)?) {
        core.setLocalTimeZone(zone: zone.map { CoreLocalTimeZone($0) })
    }

    public func connectionState(
        listener: any GIMClientKit.ConnectionStateListener
    ) async throws -> GIMClientKit.TaskHandle {
        let relay = MainQueueRelay()
        let handle = try await bridged {
            try await core.connectionState(listener: CoreConnectionStateListener(listener, relay: relay))
        }
        return relay.handle(handle)
    }

    public func typing(
        chatId: String, listener: any GIMClientKit.TypingListener
    ) async throws -> GIMClientKit.TaskHandle {
        let relay = MainQueueRelay()
        let handle = try await bridged {
            try await core.typing(chatId: chatId, listener: CoreTypingListener(listener, relay: relay))
        }
        return relay.handle(handle)
    }

    public func hubs() async throws -> [GIMClientKit.HubInfo] {
        try await bridged { try await core.hubs().map { GIMClientKit.HubInfo($0) } }
    }

    public func addHub(url: String) async throws -> GIMClientKit.HubInfo {
        try await bridged { try await GIMClientKit.HubInfo(core.addHub(url: url)) }
    }

    public func removeHub(hubId: String, confirmOwnedGroups: Bool) async throws {
        try await bridged { try await core.removeHub(hubId: hubId, confirmOwnedGroups: confirmOwnedGroups) }
    }

    public func setPrimaryHub(hubId: String) async throws {
        try await bridged { try await core.setPrimaryHub(hubId: hubId) }
    }

    public func hubList(listener: any GIMClientKit.HubListListener) async throws -> GIMClientKit.TaskHandle {
        let relay = MainQueueRelay()
        let handle = try await bridged {
            try await core.hubList(listener: CoreHubListListener(listener, relay: relay))
        }
        return relay.handle(handle)
    }

    public func registerPush(registration: GIMClientKit.PushRegistration) async throws {
        try await bridged { try await core.registerPush(registration: GIMCore.PushRegistration(registration)) }
    }

    public func unregisterPush() async throws {
        try await bridged { try await core.unregisterPush() }
    }

    public func processPush(payload: String) async throws -> GIMClientKit.NotificationContent {
        try await bridged { try await GIMClientKit.NotificationContent(core.processPush(payload: payload)) }
    }

    public func ownProfile() async throws -> GIMClientKit.UserProfile? {
        try await bridged { try await core.ownProfile().map { GIMClientKit.UserProfile($0) } }
    }

    public func setAvatar(filePath: String, mime: String) async throws {
        try await bridged { try await core.setAvatar(filePath: filePath, mime: mime) }
    }

    public func removeAvatar() async throws {
        try await bridged { try await core.removeAvatar() }
    }

    public func fetchUserAvatar(userId: String, destPath: String) async throws -> String {
        try await bridged { try await core.fetchUserAvatar(userId: userId, destPath: destPath) }
    }

    public func fetchChatAvatar(chatId: String, destPath: String) async throws -> String {
        try await bridged { try await core.fetchChatAvatar(chatId: chatId, destPath: destPath) }
    }

    public func privacy() async throws -> GIMClientKit.PrivacySettings {
        try await bridged { try await GIMClientKit.PrivacySettings(core.privacy()) }
    }

    public func setReadReceipts(enabled: Bool) async throws {
        try await bridged { try await core.setReadReceipts(enabled: enabled) }
    }

    public func setTypingIndicators(enabled: Bool) async throws {
        try await bridged { try await core.setTypingIndicators(enabled: enabled) }
    }

    public func blockUser(userId: String) async throws {
        try await bridged { try await core.blockUser(userId: userId) }
    }

    public func unblockUser(userId: String) async throws {
        try await bridged { try await core.unblockUser(userId: userId) }
    }

    public func setChatMuted(chatId: String, mutedUntilMs: UInt64) async throws {
        try await bridged { try await core.setChatMuted(chatId: chatId, mutedUntilMs: mutedUntilMs) }
    }

    public func setChatPinned(chatId: String, pinned: Bool) async throws {
        try await bridged { try await core.setChatPinned(chatId: chatId, pinned: pinned) }
    }

    public func setChatArchived(chatId: String, archived: Bool) async throws {
        try await bridged { try await core.setChatArchived(chatId: chatId, archived: archived) }
    }

    public func reportUser(
        userId: String, reason: GIMClientKit.ReportReason, note: String?, messageIds: [String]
    ) async throws -> String {
        try await bridged {
            try await core.reportUser(
                userId: userId, reason: GIMCore.ReportReason(reason), note: note, messageIds: messageIds)
        }
    }

    public func rotateRecoveryCode() async throws -> GIMClientKit.RecoveryRotation {
        try await bridged { try await GIMClientKit.RecoveryRotation(core.rotateRecoveryCode()) }
    }

    public func deleteAccount() async throws -> [String] {
        try await bridged { try await core.deleteAccount() }
    }
}

/// Adapts gim-core's generated `Timeline` object to the mirror `Timeline` protocol.
final class RealTimeline: GIMClientKit.Timeline {
    private let core: GIMCore.Timeline

    init(_ core: GIMCore.Timeline) {
        self.core = core
    }

    func chatId() -> String {
        core.chatId()
    }

    func addListener(listener: any GIMClientKit.TimelineListener) async -> GIMClientKit.TaskHandle {
        let relay = MainQueueRelay()
        return relay.handle(await core.addListener(listener: CoreTimelineListener(listener, relay: relay)))
    }

    func paginateBackwards(count: UInt16) async throws -> Bool {
        try await bridged { try await core.paginateBackwards(count: count) }
    }

    func chatState() -> GIMClientKit.ChatState? {
        core.chatState().map { GIMClientKit.ChatState($0) }
    }
}

/// Adapts gim-core's generated `LinkSession` object to the mirror `LinkSession` protocol.
final class RealLinkSession: GIMClientKit.LinkSession {
    let core: GIMCore.LinkSession

    init(_ core: GIMCore.LinkSession) {
        self.core = core
    }

    func qrString() -> String {
        core.qrString()
    }
}

/// Adapts gim-core's generated `PendingApproval` object to the mirror `PendingApproval` protocol.
final class RealPendingApproval: GIMClientKit.PendingApproval {
    let core: GIMCore.PendingApproval

    init(_ core: GIMCore.PendingApproval) {
        self.core = core
    }

    func deviceId() -> String {
        core.deviceId()
    }

    func sas() -> String {
        core.sas()
    }
}
