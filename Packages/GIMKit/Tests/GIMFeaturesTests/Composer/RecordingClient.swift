import Foundation
import GIMClientKit

/// Forwards to a `FakeGimClient`, records the composer and message-action calls and can fail them.
actor RecordingClient: GimClientAPI {
    enum Call: Hashable {
        case sendText(body: String, replyTo: String?)
        case sendMedia(mime: String, replyTo: String?)
        case edit(messageId: String, newBody: String)
        case delete(messageId: String)
        case cancelSend(messageId: String)
        case react(messageId: String, emoji: String)
        case unreact(messageId: String, emoji: String)
        case typing(Bool)
    }

    let fake: FakeGimClient
    private(set) var calls: [Call] = []
    /// Thrown by the next recorded call other than typing, then cleared.
    private var nextError: GimError?

    init(_ fake: FakeGimClient) {
        self.fake = fake
    }

    func failNext(with error: GimError) {
        nextError = error
    }

    var typingCalls: [Bool] {
        calls.compactMap { if case .typing(let active) = $0 { active } else { nil } }
    }

    private func record(_ call: Call) throws {
        calls.append(call)
        if case .typing = call { return }
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    // MARK: - Recorded

    func sendText(chatId: String, body: String, replyTo: String?) async throws -> String {
        try record(.sendText(body: body, replyTo: replyTo))
        return try await fake.sendText(chatId: chatId, body: body, replyTo: replyTo)
    }

    func sendMedia(
        chatId: String, filePath: String, mime: String, caption: String?, replyTo: String?
    ) async throws -> String {
        try record(.sendMedia(mime: mime, replyTo: replyTo))
        return try await fake.sendMedia(
            chatId: chatId, filePath: filePath, mime: mime, caption: caption, replyTo: replyTo)
    }

    func editMessage(chatId: String, messageId: String, newBody: String) async throws {
        try record(.edit(messageId: messageId, newBody: newBody))
        try await fake.editMessage(chatId: chatId, messageId: messageId, newBody: newBody)
    }

    func deleteMessage(chatId: String, messageId: String) async throws {
        try record(.delete(messageId: messageId))
        try await fake.deleteMessage(chatId: chatId, messageId: messageId)
    }

    func cancelSend(chatId: String, messageId: String) async throws {
        try record(.cancelSend(messageId: messageId))
        try await fake.cancelSend(chatId: chatId, messageId: messageId)
    }

    func react(chatId: String, messageId: String, emoji: String) async throws {
        try record(.react(messageId: messageId, emoji: emoji))
        try await fake.react(chatId: chatId, messageId: messageId, emoji: emoji)
    }

    func unreact(chatId: String, messageId: String, emoji: String) async throws {
        try record(.unreact(messageId: messageId, emoji: emoji))
        try await fake.unreact(chatId: chatId, messageId: messageId, emoji: emoji)
    }

    func setTyping(chatId: String, active: Bool) async throws {
        try record(.typing(active))
        try await fake.setTyping(chatId: chatId, active: active)
    }

    // MARK: - Forwarded

    func session() async throws -> Session? { try await fake.session() }
    nonisolated func userId() -> String? { fake.userId() }
    nonisolated func recoveryCode() throws -> String? { try fake.recoveryCode() }
    nonisolated func localStateReset() -> Bool { fake.localStateReset() }
    func createIdentity(displayName: String) async throws -> String {
        try await fake.createIdentity(displayName: displayName)
    }
    func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws {
        try await fake.restoreFromRecovery(userId: userId, recoveryCode: recoveryCode, revokeOthers: revokeOthers)
    }
    nonisolated func startLink(hubs: [String]) throws -> any LinkSession { try fake.startLink(hubs: hubs) }
    func waitLink(link: any LinkSession) async throws -> String { try await fake.waitLink(link: link) }
    func confirmLink(accepted: Bool) async throws { try await fake.confirmLink(accepted: accepted) }
    func approveLink(qrString: String) async throws -> any PendingApproval {
        try await fake.approveLink(qrString: qrString)
    }
    func confirmApproval(approval: any PendingApproval, accepted: Bool) async throws {
        try await fake.confirmApproval(approval: approval, accepted: accepted)
    }
    func devices() async throws -> [DeviceInfo] { try await fake.devices() }
    func userDevices(userId: String) async throws -> [DeviceInfo] { try await fake.userDevices(userId: userId) }
    func revokeDevice(deviceId: String) async throws { try await fake.revokeDevice(deviceId: deviceId) }
    func setDisplayName(name: String) async throws { try await fake.setDisplayName(name: name) }
    func stopTyping(chatId: String) async throws { try await fake.stopTyping(chatId: chatId) }
    func signOut() async throws { try await fake.signOut() }
    func startSync() async throws { try await fake.startSync() }
    func stopSync() async throws { try await fake.stopSync() }
    nonisolated func setNetworkReachable(reachable: Bool) { fake.setNetworkReachable(reachable: reachable) }
    nonisolated func setLocalTimeZone(zone: (any LocalTimeZone)?) { fake.setLocalTimeZone(zone: zone) }
    func createDirectChat(userId: String) async throws -> String { try await fake.createDirectChat(userId: userId) }
    func createGroupChat(name: String, memberUserIds: [String]) async throws -> String {
        try await fake.createGroupChat(name: name, memberUserIds: memberUserIds)
    }
    func chatMembers(chatId: String) async throws -> [UserProfile] { try await fake.chatMembers(chatId: chatId) }
    func addMembers(chatId: String, userIds: [String]) async throws {
        try await fake.addMembers(chatId: chatId, userIds: userIds)
    }
    func removeMember(chatId: String, userId: String) async throws {
        try await fake.removeMember(chatId: chatId, userId: userId)
    }
    func leaveChat(chatId: String) async throws { try await fake.leaveChat(chatId: chatId) }
    func chatState(chatId: String) async throws -> ChatState { try await fake.chatState(chatId: chatId) }
    func setGroupInfo(chatId: String, name: String?, avatarFilePath: String?) async throws {
        try await fake.setGroupInfo(chatId: chatId, name: name, avatarFilePath: avatarFilePath)
    }
    func retrySend(chatId: String, messageId: String) async throws {
        try await fake.retrySend(chatId: chatId, messageId: messageId)
    }
    func markRead(chatId: String, upToMessageId: String) async throws {
        try await fake.markRead(chatId: chatId, upToMessageId: upToMessageId)
    }
    func fetchMedia(chatId: String, messageId: String, destPath: String) async throws -> String {
        try await fake.fetchMedia(chatId: chatId, messageId: messageId, destPath: destPath)
    }
    func fetchThumbnail(chatId: String, messageId: String, destPath: String) async throws -> String? {
        try await fake.fetchThumbnail(chatId: chatId, messageId: messageId, destPath: destPath)
    }
    func chatList(listener: any ChatListListener) async throws -> TaskHandle {
        try await fake.chatList(listener: listener)
    }
    func timeline(chatId: String) async throws -> any Timeline { try await fake.timeline(chatId: chatId) }
    func connectionState(listener: any ConnectionStateListener) async throws -> TaskHandle {
        try await fake.connectionState(listener: listener)
    }
    func typing(chatId: String, listener: any TypingListener) async throws -> TaskHandle {
        try await fake.typing(chatId: chatId, listener: listener)
    }

    func hubs() async throws -> [HubInfo] {
        try await fake.hubs()
    }

    func addHub(url: String) async throws -> HubInfo {
        try await fake.addHub(url: url)
    }

    func removeHub(hubId: String, confirmOwnedGroups: Bool) async throws {
        try await fake.removeHub(hubId: hubId, confirmOwnedGroups: confirmOwnedGroups)
    }

    func setPrimaryHub(hubId: String) async throws {
        try await fake.setPrimaryHub(hubId: hubId)
    }

    func hubList(listener: any HubListListener) async throws -> TaskHandle {
        try await fake.hubList(listener: listener)
    }

    func registerPush(registration: PushRegistration) async throws {
        try await fake.registerPush(registration: registration)
    }

    func unregisterPush() async throws {
        try await fake.unregisterPush()
    }

    func processPush(payload: String) async throws -> NotificationContent {
        try await fake.processPush(payload: payload)
    }

    func ownProfile() async throws -> UserProfile? {
        try await fake.ownProfile()
    }

    func setAvatar(filePath: String, mime: String) async throws {
        try await fake.setAvatar(filePath: filePath, mime: mime)
    }

    func removeAvatar() async throws {
        try await fake.removeAvatar()
    }

    func fetchUserAvatar(userId: String, destPath: String) async throws -> String {
        try await fake.fetchUserAvatar(userId: userId, destPath: destPath)
    }

    func fetchChatAvatar(chatId: String, destPath: String) async throws -> String {
        try await fake.fetchChatAvatar(chatId: chatId, destPath: destPath)
    }

    func privacy() async throws -> PrivacySettings {
        try await fake.privacy()
    }

    func setReadReceipts(enabled: Bool) async throws {
        try await fake.setReadReceipts(enabled: enabled)
    }

    func setTypingIndicators(enabled: Bool) async throws {
        try await fake.setTypingIndicators(enabled: enabled)
    }

    func blockUser(userId: String) async throws {
        try await fake.blockUser(userId: userId)
    }

    func unblockUser(userId: String) async throws {
        try await fake.unblockUser(userId: userId)
    }

    func setChatMuted(chatId: String, mutedUntilMs: UInt64) async throws {
        try await fake.setChatMuted(chatId: chatId, mutedUntilMs: mutedUntilMs)
    }

    func setChatPinned(chatId: String, pinned: Bool) async throws {
        try await fake.setChatPinned(chatId: chatId, pinned: pinned)
    }

    func setChatArchived(chatId: String, archived: Bool) async throws {
        try await fake.setChatArchived(chatId: chatId, archived: archived)
    }

    func reportUser(userId: String, reason: ReportReason, note: String?, messageIds: [String]) async throws -> String {
        try await fake.reportUser(userId: userId, reason: reason, note: note, messageIds: messageIds)
    }

    func rotateRecoveryCode() async throws -> RecoveryRotation {
        try await fake.rotateRecoveryCode()
    }

    func deleteAccount() async throws -> [String] {
        try await fake.deleteAccount()
    }
}

/// A message for composer and menu tests; only the fields the rules look at matter.
func makeMessage(
    id: String = "m1", isOwn: Bool = true, content: MessageContent = .text(body: "Hello"),
    reactions: [ReactionGroup] = [], sendState: SendState? = .sent
) -> MessageItem {
    MessageItem(
        messageId: id, chatId: FakeGimClient.demoDirectChatId,
        sender: UserProfile(userId: "u", displayName: "U"), isOwn: isOwn,
        sentAtMs: 0, content: content, replyTo: nil, reactions: reactions, edited: false,
        sendState: isOwn ? sendState : nil)
}

/// Mutable clock for the typing throttle.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_791_000_000)

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}
