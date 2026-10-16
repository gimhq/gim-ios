import Foundation
import GIMClientKit
import Synchronization

/// The link calls of every `LinkRecordingClient` sharing it, in completion order, e.g. `"new.waitLink"`.
final class LinkCallLog: Sendable {
    private let entries = Mutex<[String]>([])

    var calls: [String] { entries.withLock { $0 } }

    func append(_ call: String) {
        entries.withLock { $0.append(call) }
    }
}

/// Blocks callers of `wait()` until `open()`.
actor LinkGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// Forwards to a `FakeGimClient` and records the link calls as `"<name>.<call>"` once they returned. `waitLink`
/// waits for `waitLinkGate` and throws the next of `waitLinkErrors` first. With `waitLinkFailsAfterBundle` those
/// failures happen after the bundle arrived: like gim-core, waiting again on that link session throws `InvalidInput`.
actor LinkRecordingClient: GimClientAPI {
    let fake: FakeGimClient
    let name: String
    let log: LinkCallLog
    let waitLinkGate: LinkGate?
    let waitLinkFailsAfterBundle: Bool
    private var waitLinkErrors: [GimError]
    /// QR strings of the link sessions a failure after the bundle used up.
    private var usedUpLinks: Set<String> = []

    init(
        _ fake: FakeGimClient = FakeGimClient(), name: String, log: LinkCallLog, waitLinkGate: LinkGate? = nil,
        waitLinkErrors: [GimError] = [], waitLinkFailsAfterBundle: Bool = false
    ) {
        self.fake = fake
        self.name = name
        self.log = log
        self.waitLinkGate = waitLinkGate
        self.waitLinkErrors = waitLinkErrors
        self.waitLinkFailsAfterBundle = waitLinkFailsAfterBundle
    }

    nonisolated func startLink(hubs: [String]) throws -> any LinkSession {
        let link = try fake.startLink(hubs: hubs)
        log.append("\(name).startLink(\(hubs.joined(separator: ",")))")
        return link
    }
    func waitLink(link: any LinkSession) async throws -> String {
        await waitLinkGate?.wait()
        if usedUpLinks.contains(link.qrString()) {
            log.append("\(name).waitLink used up")
            throw GimError.InvalidInput(reason: "the link session was used; start a new one")
        }
        if !waitLinkErrors.isEmpty {
            log.append("\(name).waitLink failed")
            if waitLinkFailsAfterBundle { usedUpLinks.insert(link.qrString()) }
            throw waitLinkErrors.removeFirst()
        }
        let sas = try await fake.waitLink(link: link)
        log.append("\(name).waitLink")
        return sas
    }
    func confirmLink(accepted: Bool) async throws {
        try await fake.confirmLink(accepted: accepted)
        log.append("\(name).confirmLink(\(accepted))")
    }
    func approveLink(qrString: String) async throws -> any PendingApproval {
        let approval = try await fake.approveLink(qrString: qrString)
        log.append("\(name).approveLink")
        return approval
    }
    func confirmApproval(approval: any PendingApproval, accepted: Bool) async throws {
        try await fake.confirmApproval(approval: approval, accepted: accepted)
        log.append("\(name).confirmApproval(\(accepted))")
    }
    func revokeDevice(deviceId: String) async throws {
        try await fake.revokeDevice(deviceId: deviceId)
        log.append("\(name).revokeDevice(\(deviceId))")
    }

    func signOut() async throws { try await fake.signOut() }
    func session() async throws -> Session? { try await fake.session() }
    nonisolated func userId() -> String? { fake.userId() }
    nonisolated func localStateReset() -> Bool { fake.localStateReset() }
    func createIdentity(displayName: String) async throws -> String {
        try await fake.createIdentity(displayName: displayName)
    }
    func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws {
        try await fake.restoreFromRecovery(userId: userId, recoveryCode: recoveryCode, revokeOthers: revokeOthers)
    }
    func devices() async throws -> [DeviceInfo] { try await fake.devices() }
    func userDevices(userId: String) async throws -> [DeviceInfo] { try await fake.userDevices(userId: userId) }
    func setDisplayName(name: String) async throws { try await fake.setDisplayName(name: name) }
    func claimHandle(handle: String) async throws { try await fake.claimHandle(handle: handle) }
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

/// Polls `condition` on the main actor until it holds or about two seconds passed.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
