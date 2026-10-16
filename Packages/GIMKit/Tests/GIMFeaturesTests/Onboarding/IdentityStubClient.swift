import Foundation
import GIMClientKit

/// Forwards to a `FakeGimClient`; `createIdentity` and `restoreFromRecovery` throw the next of their configured
/// errors first (keeping nothing, like gim-core), `claimHandle` throws its configured error.
actor IdentityStubClient: GimClientAPI {
    let fake: FakeGimClient
    let claimHandleError: GimError?
    private var createIdentityErrors: [GimError]
    private var restoreErrors: [GimError]

    init(
        _ fake: FakeGimClient = FakeGimClient(), createIdentityErrors: [GimError] = [], restoreErrors: [GimError] = [],
        claimHandleError: GimError? = nil
    ) {
        self.fake = fake
        self.createIdentityErrors = createIdentityErrors
        self.restoreErrors = restoreErrors
        self.claimHandleError = claimHandleError
    }

    func signOut() async throws { try await fake.signOut() }
    func session() async throws -> Session? { try await fake.session() }
    nonisolated func userId() -> String? { fake.userId() }
    nonisolated func localStateReset() -> Bool { fake.localStateReset() }
    func createIdentity(displayName: String) async throws -> String {
        if !createIdentityErrors.isEmpty { throw createIdentityErrors.removeFirst() }
        return try await fake.createIdentity(displayName: displayName)
    }
    func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws {
        if !restoreErrors.isEmpty { throw restoreErrors.removeFirst() }
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
    func claimHandle(handle: String) async throws {
        if let claimHandleError { throw claimHandleError }
        try await fake.claimHandle(handle: handle)
    }
    func releaseHandle() async throws { try await fake.releaseHandle() }
    func stopTyping(chatId: String) async throws { try await fake.stopTyping(chatId: chatId) }
    func startSync() async throws { try await fake.startSync() }
    func stopSync() async throws { try await fake.stopSync() }
    nonisolated func setNetworkReachable(reachable: Bool) { fake.setNetworkReachable(reachable: reachable) }
    nonisolated func setLocalTimeZone(zone: (any LocalTimeZone)?) { fake.setLocalTimeZone(zone: zone) }
    func findUser(handle: String) async throws -> UserProfile? { try await fake.findUser(handle: handle) }
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
    func sendText(chatId: String, body: String, replyTo: String?) async throws -> String {
        try await fake.sendText(chatId: chatId, body: body, replyTo: replyTo)
    }
    func sendMedia(
        chatId: String, filePath: String, mime: String, caption: String?, replyTo: String?
    ) async throws -> String {
        try await fake.sendMedia(chatId: chatId, filePath: filePath, mime: mime, caption: caption, replyTo: replyTo)
    }
    func editMessage(chatId: String, messageId: String, newBody: String) async throws {
        try await fake.editMessage(chatId: chatId, messageId: messageId, newBody: newBody)
    }
    func deleteMessage(chatId: String, messageId: String) async throws {
        try await fake.deleteMessage(chatId: chatId, messageId: messageId)
    }
    func react(chatId: String, messageId: String, emoji: String) async throws {
        try await fake.react(chatId: chatId, messageId: messageId, emoji: emoji)
    }
    func unreact(chatId: String, messageId: String, emoji: String) async throws {
        try await fake.unreact(chatId: chatId, messageId: messageId, emoji: emoji)
    }
    func retrySend(chatId: String, messageId: String) async throws {
        try await fake.retrySend(chatId: chatId, messageId: messageId)
    }
    func cancelSend(chatId: String, messageId: String) async throws {
        try await fake.cancelSend(chatId: chatId, messageId: messageId)
    }
    func markRead(chatId: String, upToMessageId: String) async throws {
        try await fake.markRead(chatId: chatId, upToMessageId: upToMessageId)
    }
    func setTyping(chatId: String, active: Bool) async throws {
        try await fake.setTyping(chatId: chatId, active: active)
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
}
