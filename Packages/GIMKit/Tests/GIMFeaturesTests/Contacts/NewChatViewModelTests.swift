import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class NewChatViewModelTests: XCTestCase {
    @MainActor
    private func makeViewModel(client: any GimClientAPI) -> (NewChatViewModel, ManualSleeper) {
        let sleeper = ManualSleeper()
        let viewModel = NewChatViewModel(client: client, sleep: { try await sleeper.sleep($0) })
        return (viewModel, sleeper)
    }

    @MainActor
    func testTypingDebouncesToOneSearch() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "s"
        viewModel.query = "so"
        viewModel.query = " Sofia "
        XCTAssertEqual(viewModel.state, .searching)

        await eventually { sleeper.pendingCount == 1 }
        await settle()
        XCTAssertEqual(sleeper.pendingCount, 1)
        XCTAssertTrue(sleeper.durations.allSatisfy { $0 == .milliseconds(300) })
        XCTAssertEqual(viewModel.state, .searching)

        sleeper.releaseAll()

        await eventually { viewModel.state != .searching }
        guard case .found(let user) = viewModel.state else { return XCTFail("Expected found, got \(viewModel.state)") }
        XCTAssertEqual(user.handle, "sofia")
    }

    @MainActor
    func testNewQueryCancelsPendingSearch() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "sofia"
        await eventually { sleeper.pendingCount == 1 }
        viewModel.query = "nobody"
        await eventually { sleeper.durations.count == 2 && sleeper.pendingCount == 1 }

        sleeper.releaseAll()

        await eventually { viewModel.state == .notFound }
    }

    @MainActor
    func testClearingQueryReturnsToIdle() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "sofia"
        await eventually { sleeper.pendingCount == 1 }
        viewModel.query = "  "

        XCTAssertEqual(viewModel.state, .idle)
        await eventually { sleeper.pendingCount == 0 }
        await settle()
        XCTAssertEqual(viewModel.state, .idle)
    }

    @MainActor
    func testSearchErrorIsPresented() async {
        let (viewModel, sleeper) = makeViewModel(client: FakeGimClient())

        viewModel.query = "sofia"
        await eventually { sleeper.pendingCount == 1 }
        sleeper.releaseAll()

        await eventually { viewModel.state == .error(ErrorPresenter.message(for: GimError.NotRegistered)) }
    }

    @MainActor
    func testStartChatReturnsDirectChat() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, sleeper) = makeViewModel(client: client)

        let none = await viewModel.startChat()
        XCTAssertNil(none)

        viewModel.query = "sofia"
        await eventually { sleeper.pendingCount == 1 }
        sleeper.releaseAll()
        await eventually { viewModel.state != .searching }

        let chatId = await viewModel.startChat()
        XCTAssertEqual(chatId, FakeGimClient.demoDirectChatId)
        XCTAssertNil(viewModel.startError)
        XCTAssertFalse(viewModel.isStarting)
    }

    @MainActor
    func testStartChatWithSelfShowsError() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "alex"
        await eventually { sleeper.pendingCount == 1 }
        sleeper.releaseAll()
        await eventually { viewModel.state != .searching }

        let chatId = await viewModel.startChat()
        XCTAssertNil(chatId)
        XCTAssertEqual(
            viewModel.startError,
            ErrorPresenter.message(for: GimError.InvalidInput(reason: "You can't start a chat with yourself")))
    }

    @MainActor
    func testStartChatWithUserWithoutDeviceShowsNotFound() async {
        let (client, _) = await connected(makeDemoClient())
        await client.addRemoteUser(UserProfile(userId: "user-kai", handle: "kai", displayName: "Kai"), hasDevice: false)
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "kai"
        await eventually { sleeper.pendingCount == 1 }
        sleeper.releaseAll()
        await eventually { viewModel.state != .searching }

        let chatId = await viewModel.startChat()
        XCTAssertNil(chatId)
        XCTAssertEqual(viewModel.startError, "No one has this username.")
    }

    @MainActor
    func testStartChatWithAUserWhoseHubRefusesShowsTheirName() async {
        let (client, _) = await connected(makeDemoClient())
        await client.refuseContacts(["user-luca"])
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "luca"
        await eventually { sleeper.pendingCount == 1 }
        sleeper.releaseAll()
        await eventually { viewModel.state != .searching }

        let chatId = await viewModel.startChat()
        XCTAssertNil(chatId)
        XCTAssertEqual(viewModel.startError, "Luca Bianchi doesn't accept messages from you.")
    }

    // MARK: - Scanned Account ID

    private static let validUserId = "u" + String(repeating: "a", count: 55)

    @MainActor
    func testScannedTextWithoutAccountIDDoesNotCallClient() async {
        let client = DirectChatStubClient()
        let (viewModel, _) = makeViewModel(client: client)

        let result = await viewModel.startChat(scanned: "user-alex")

        XCTAssertEqual(result, .noUserId)
        let calls = await client.directChatUserIds
        XCTAssertEqual(calls, [])
        XCTAssertNil(viewModel.startError)
    }

    @MainActor
    func testScannedAccountIDStartsDirectChat() async {
        let client = DirectChatStubClient()
        let (viewModel, _) = makeViewModel(client: client)

        let result = await viewModel.startChat(scanned: "Account ID: \(Self.validUserId.uppercased())")

        XCTAssertEqual(result, .started(chatId: "chat-9"))
        let calls = await client.directChatUserIds
        XCTAssertEqual(calls, [Self.validUserId])
        XCTAssertNil(viewModel.startError)
        XCTAssertFalse(viewModel.isStarting)
    }

    @MainActor
    func testScannedUnknownAccountIDShowsNotFound() async {
        let client = DirectChatStubClient(error: .NotFound(reason: "x"))
        let (viewModel, _) = makeViewModel(client: client)

        let result = await viewModel.startChat(scanned: Self.validUserId)

        XCTAssertEqual(result, .failed(NewChatViewModel.notFoundMessage))
        XCTAssertEqual(viewModel.startError, NewChatViewModel.notFoundMessage)
        XCTAssertFalse(viewModel.isStarting)
    }
}

/// Forwards to a `FakeGimClient`; `createDirectChat` records the id and returns `chat-9` or throws `error`.
private actor DirectChatStubClient: GimClientAPI {
    let fake = FakeGimClient()
    private(set) var directChatUserIds: [String] = []
    private let error: GimError?

    init(error: GimError? = nil) {
        self.error = error
    }

    func createDirectChat(userId: String) async throws -> String {
        directChatUserIds.append(userId)
        if let error { throw error }
        return "chat-9"
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
    func cancelSend(chatId: String, messageId: String) async throws {
        try await fake.cancelSend(chatId: chatId, messageId: messageId)
    }
    func react(chatId: String, messageId: String, emoji: String) async throws {
        try await fake.react(chatId: chatId, messageId: messageId, emoji: emoji)
    }
    func unreact(chatId: String, messageId: String, emoji: String) async throws {
        try await fake.unreact(chatId: chatId, messageId: messageId, emoji: emoji)
    }
    func setTyping(chatId: String, active: Bool) async throws {
        try await fake.setTyping(chatId: chatId, active: active)
    }
    func session() async throws -> Session? { try await fake.session() }
    nonisolated func userId() -> String? { fake.userId() }
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
    func claimHandle(handle: String) async throws { try await fake.claimHandle(handle: handle) }
    func releaseHandle() async throws { try await fake.releaseHandle() }
    func stopTyping(chatId: String) async throws { try await fake.stopTyping(chatId: chatId) }
    func signOut() async throws { try await fake.signOut() }
    func startSync() async throws { try await fake.startSync() }
    func stopSync() async throws { try await fake.stopSync() }
    nonisolated func setNetworkReachable(reachable: Bool) { fake.setNetworkReachable(reachable: reachable) }
    nonisolated func setLocalTimeZone(zone: (any LocalTimeZone)?) { fake.setLocalTimeZone(zone: zone) }
    func findUser(handle: String) async throws -> UserProfile? { try await fake.findUser(handle: handle) }
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

    func ownProfile() async throws -> UserProfile? { try await fake.ownProfile() }
    func setAvatar(filePath: String, mime: String) async throws {
        try await fake.setAvatar(filePath: filePath, mime: mime)
    }
    func removeAvatar() async throws { try await fake.removeAvatar() }
    func fetchUserAvatar(userId: String, destPath: String) async throws -> String {
        try await fake.fetchUserAvatar(userId: userId, destPath: destPath)
    }
    func fetchChatAvatar(chatId: String, destPath: String) async throws -> String {
        try await fake.fetchChatAvatar(chatId: chatId, destPath: destPath)
    }
    func privacy() async throws -> PrivacySettings { try await fake.privacy() }
    func setReadReceipts(enabled: Bool) async throws { try await fake.setReadReceipts(enabled: enabled) }
    func setTypingIndicators(enabled: Bool) async throws { try await fake.setTypingIndicators(enabled: enabled) }
    func blockUser(userId: String) async throws { try await fake.blockUser(userId: userId) }
    func unblockUser(userId: String) async throws { try await fake.unblockUser(userId: userId) }
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
    func rotateRecoveryCode() async throws -> RecoveryRotation { try await fake.rotateRecoveryCode() }
    func deleteAccount() async throws -> [String] { try await fake.deleteAccount() }
}
