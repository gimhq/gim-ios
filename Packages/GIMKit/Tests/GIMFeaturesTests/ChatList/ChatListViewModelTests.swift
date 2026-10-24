import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class ChatListViewModelTests: XCTestCase {
    @MainActor
    private func startedViewModel(_ client: any GimClientAPI) async -> ChatListViewModel {
        let viewModel = ChatListViewModel(client: client, dateFormatter: makeFormatter(), now: { fixedNow })
        XCTAssertTrue(viewModel.isLoading)
        viewModel.start()
        await eventually { viewModel.rows.count == 2 }
        return viewModel
    }

    @MainActor
    func testInitialResetMapsRows() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.rows.map(\.id), [FakeGimClient.demoGroupChatId, FakeGimClient.demoDirectChatId])
        let group = viewModel.rows[0]
        XCTAssertEqual(group.title, "Aegean Crew")
        XCTAssertEqual(group.preview, "Nikos Papadopoulos: Me, grilled octopus 🐙")
        XCTAssertEqual(group.unreadText, "3")
        XCTAssertNotNil(group.time)
        let direct = viewModel.rows[1]
        XCTAssertEqual(direct.title, "Sofia Marin")
        XCTAssertEqual(direct.unreadText, "2")
        await eventually { viewModel.connectionState == .connected }
    }

    @MainActor
    func testNewMessageReordersViaRemoveAndInsert() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        try await client.receiveText(chatId: FakeGimClient.demoDirectChatId, from: "user-sofia", body: "On my way")

        await eventually { viewModel.rows.first?.id == FakeGimClient.demoDirectChatId }
        XCTAssertEqual(viewModel.rows.map(\.id), [FakeGimClient.demoDirectChatId, FakeGimClient.demoGroupChatId])
        XCTAssertEqual(viewModel.rows[0].preview, "On my way")
        XCTAssertEqual(viewModel.rows[0].unreadText, "3")
    }

    @MainActor
    func testUpdateInPlaceAndDeletedPreview() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        try await client.markRead(chatId: FakeGimClient.demoGroupChatId, upToMessageId: "msg-crew-5")
        await eventually { viewModel.rows[0].unreadText == nil }

        let id = try await client.sendText(chatId: FakeGimClient.demoGroupChatId, body: "Wrong chat", replyTo: nil)
        try await client.deleteMessage(chatId: FakeGimClient.demoGroupChatId, messageId: id)
        await eventually { viewModel.rows[0].preview == "Alex Morgan: Message deleted" }
    }

    @MainActor
    func testNewChatIsInserted() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        let chatId = try await client.createGroupChat(name: "Regatta", memberUserIds: ["user-sofia", "user-luca"])

        await eventually { viewModel.rows.count == 3 }
        XCTAssertEqual(viewModel.rows.first?.id, chatId)
        XCTAssertNil(viewModel.rows.first?.preview)
    }

    @MainActor
    func testConnectionStateFollowsClient() async {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.connectionState == .connected }

        client.setNetworkReachable(reachable: false)
        await eventually { viewModel.connectionState == .offline }

        await client.simulateNetworkReachable(true)
        await eventually { viewModel.connectionState == .connecting }
        await scheduler.advance(by: .milliseconds(500))
        await eventually { viewModel.connectionState == .syncing }
        await scheduler.runUntilIdle()
        await eventually { viewModel.connectionState == .connected }
    }

    @MainActor
    func testStopUnsubscribes() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        viewModel.stop()
        await settle()
        try await client.markRead(chatId: FakeGimClient.demoGroupChatId, upToMessageId: "msg-crew-5")
        await settle()

        XCTAssertEqual(viewModel.rows[0].unreadText, "3")
    }

    @MainActor
    func testRefreshResubscribesWithReset() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        viewModel.stop()
        await settle()
        try await client.markRead(chatId: FakeGimClient.demoGroupChatId, upToMessageId: "msg-crew-5")

        viewModel.refresh()

        await eventually { viewModel.rows[0].unreadText == nil }
        try await client.receiveText(chatId: FakeGimClient.demoGroupChatId, from: "user-luca", body: "Anchor's up")
        await eventually { viewModel.rows[0].preview == "Luca Bianchi: Anchor's up" }
    }

    @MainActor
    func testSubscribeFailureShowsError() async {
        let client = FailingChatListClient()
        let viewModel = ChatListViewModel(client: client, dateFormatter: makeFormatter())

        viewModel.start()

        await eventually { viewModel.errorMessage != nil }
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.NotRegistered))
    }

    @MainActor
    func testSubtitleFollowsChatStateAfterOwnLeave() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let groupId = FakeGimClient.demoGroupChatId
        XCTAssertEqual(
            viewModel.subtitle(for: try row(groupId, viewModel)), "Nikos Papadopoulos: Me, grilled octopus 🐙")

        try await client.leaveChat(chatId: groupId)

        await eventually { (try? self.row(groupId, viewModel).state) == .leaving }
        XCTAssertEqual(viewModel.subtitle(for: try row(groupId, viewModel)), "Leaving…")
        let direct = try row(FakeGimClient.demoDirectChatId, viewModel)
        XCTAssertEqual(viewModel.subtitle(for: direct), direct.preview)
        await settle()
        await scheduler.advance(by: FakeGimClient.leaveCommitDelay)
        await eventually { (try? self.row(groupId, viewModel).state) == .left }
        await eventually { (try? viewModel.subtitle(for: self.row(groupId, viewModel))) == "You left" }
        // A left chat stays in the list with its history.
        XCTAssertEqual(Set(viewModel.rows.map(\.id)), [groupId, FakeGimClient.demoDirectChatId])
    }

    @MainActor
    func testSubtitleOfChatTheUserWasRemovedFrom() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let groupId = FakeGimClient.demoGroupChatId

        try await client.simulateRemoval(chatId: groupId, by: "user-nikos")

        await eventually { (try? viewModel.subtitle(for: self.row(groupId, viewModel))) == "You were removed" }
        XCTAssertEqual(try row(groupId, viewModel).state, .left)
    }

    @MainActor
    func testLeftSubtitleWithoutOwnMembershipChange() async throws {
        let summary = ChatSummary(
            chatId: "h/g1", kind: .group, name: "Old crew", avatar: nil, lastMessage: nil, unreadCount: 0,
            updatedAtMs: 0, memberCount: 2, state: .left)
        let viewModel = ChatListViewModel(client: FakeGimClient(), dateFormatter: makeFormatter())

        XCTAssertEqual(viewModel.subtitle(for: ChatRow(summary: summary, dateFormatter: makeFormatter())), "Left")
        var leaving = summary
        leaving.state = .leaving
        XCTAssertEqual(viewModel.subtitle(for: ChatRow(summary: leaving, dateFormatter: makeFormatter())), "Leaving…")
    }

    @MainActor
    func testSubtitleKindFollowsChatStateAfterOwnLeave() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let groupId = FakeGimClient.demoGroupChatId
        XCTAssertEqual(
            viewModel.subtitleKind(for: try row(groupId, viewModel)),
            .preview("Nikos Papadopoulos: Me, grilled octopus 🐙"))

        try await client.leaveChat(chatId: groupId)

        await eventually { (try? self.row(groupId, viewModel).state) == .leaving }
        XCTAssertEqual(viewModel.subtitleKind(for: try row(groupId, viewModel)), .leaving)
        await settle()
        await scheduler.advance(by: FakeGimClient.leaveCommitDelay)
        await eventually { (try? viewModel.subtitleKind(for: self.row(groupId, viewModel))) == .left }
    }

    @MainActor
    func testSubtitleKindOfChatTheUserWasRemovedFrom() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let groupId = FakeGimClient.demoGroupChatId

        try await client.simulateRemoval(chatId: groupId, by: "user-nikos")

        await eventually { (try? viewModel.subtitleKind(for: self.row(groupId, viewModel))) == .removed }
    }

    @MainActor
    func testSubtitleKindWithoutPreviewOrOwnMembershipChange() async throws {
        let summary = ChatSummary(
            chatId: "h/g1", kind: .group, name: "Old crew", avatar: nil, lastMessage: nil, unreadCount: 0,
            updatedAtMs: 0, memberCount: 2, state: .active)
        let viewModel = ChatListViewModel(client: FakeGimClient(), dateFormatter: makeFormatter())
        let active = ChatRow(summary: summary, dateFormatter: makeFormatter())

        XCTAssertEqual(viewModel.subtitleKind(for: active), .noMessages)
        XCTAssertEqual(viewModel.subtitle(for: active), "No messages yet")
        var left = summary
        left.state = .left
        XCTAssertEqual(
            viewModel.subtitleKind(for: ChatRow(summary: left, dateFormatter: makeFormatter())), .leftUnknown)
    }

    @MainActor
    func testLastMessageStatusIsNilForForeignLastMessages() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        for row in viewModel.rows {
            XCTAssertFalse(row.lastMessageIsOwn, row.id)
            XCTAssertNil(viewModel.lastMessageStatus(for: row), row.id)
        }
    }

    @MainActor
    func testLastMessageStatusFollowsTheOwnPreview() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let chatId = FakeGimClient.demoDirectChatId

        _ = try await client.sendText(chatId: chatId, body: "Ready", replyTo: nil)

        await eventually { self.lastMessageStatus(chatId, viewModel) == .sending }
        await scheduler.advance(by: .milliseconds(300))
        await eventually { self.lastMessageStatus(chatId, viewModel) == .sent }
        await scheduler.advance(by: .milliseconds(700))
        await eventually { self.lastMessageStatus(chatId, viewModel) == .delivered }
        await scheduler.advance(by: .milliseconds(1500))
        await eventually { self.lastMessageStatus(chatId, viewModel) == .read }
        XCTAssertNil(viewModel.lastMessageStatus(for: try row(FakeGimClient.demoGroupChatId, viewModel)))

        try await client.receiveText(chatId: chatId, from: "user-sofia", body: "On my way")

        await eventually { (try? self.row(chatId, viewModel).lastMessageIsOwn) == false }
        XCTAssertNil(lastMessageStatus(chatId, viewModel))
    }

    @MainActor
    func testLastMessageStatusIsNilOnceTheChatIsLeft() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let chatId = FakeGimClient.demoGroupChatId
        _ = try await client.sendText(chatId: chatId, body: "Leaving now", replyTo: nil)
        await scheduler.runUntilIdle()
        await eventually { self.lastMessageStatus(chatId, viewModel) == .read }

        try await client.leaveChat(chatId: chatId)

        await eventually { (try? self.row(chatId, viewModel).state) == .leaving }
        XCTAssertNil(lastMessageStatus(chatId, viewModel))
    }

    @MainActor
    func testPinnedChatComesFirstUntilUnpinned() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let direct = try row(FakeGimClient.demoDirectChatId, viewModel)
        XCTAssertFalse(direct.isPinned)

        await viewModel.setPinned(direct, true)

        await eventually { viewModel.rows.first?.id == FakeGimClient.demoDirectChatId }
        XCTAssertTrue(viewModel.rows[0].isPinned)
        XCTAssertFalse(viewModel.rows[1].isPinned)

        await viewModel.setPinned(viewModel.rows[0], false)

        await eventually { viewModel.rows.first?.id == FakeGimClient.demoGroupChatId }
        XCTAssertFalse(try row(FakeGimClient.demoDirectChatId, viewModel).isPinned)
        XCTAssertNil(viewModel.actionErrorMessage)
    }

    @MainActor
    func testMuteAndUnmute() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let groupId = FakeGimClient.demoGroupChatId
        XCTAssertFalse(try row(groupId, viewModel).isMuted)

        await viewModel.mute(try row(groupId, viewModel), .oneHour)
        await eventually { (try? self.row(groupId, viewModel).isMuted) == true }
        XCTAssertFalse(try row(FakeGimClient.demoDirectChatId, viewModel).isMuted)

        await viewModel.unmute(try row(groupId, viewModel))
        await eventually { (try? self.row(groupId, viewModel).isMuted) == false }

        await viewModel.mute(try row(groupId, viewModel), .always)
        await eventually { (try? self.row(groupId, viewModel).isMuted) == true }
        XCTAssertNil(viewModel.actionErrorMessage)
    }

    @MainActor
    func testArchivedChatsLeaveTheMainList() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        XCTAssertFalse(viewModel.hasArchived)
        XCTAssertEqual(viewModel.archivedRows, [])

        await viewModel.setArchived(try row(FakeGimClient.demoGroupChatId, viewModel), true)

        await eventually { viewModel.hasArchived }
        XCTAssertEqual(viewModel.rows.map(\.id), [FakeGimClient.demoDirectChatId])
        XCTAssertEqual(viewModel.archivedRows.map(\.id), [FakeGimClient.demoGroupChatId])
        XCTAssertTrue(viewModel.archivedRows[0].isArchived)

        // A new message does not unarchive the chat.
        try await client.receiveText(chatId: FakeGimClient.demoGroupChatId, from: "user-luca", body: "Anchor's up")
        await eventually { viewModel.archivedRows.first?.preview == "Luca Bianchi: Anchor's up" }
        XCTAssertEqual(viewModel.rows.map(\.id), [FakeGimClient.demoDirectChatId])

        await viewModel.setArchived(viewModel.archivedRows[0], false)

        await eventually { !viewModel.hasArchived }
        XCTAssertEqual(viewModel.rows.map(\.id), [FakeGimClient.demoGroupChatId, FakeGimClient.demoDirectChatId])
        XCTAssertEqual(viewModel.archivedRows, [])
    }

    @MainActor
    func testArchivedRowsKeepTheClientOrder() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        await viewModel.setArchived(try row(FakeGimClient.demoDirectChatId, viewModel), true)
        await viewModel.setArchived(try row(FakeGimClient.demoGroupChatId, viewModel), true)

        await eventually { viewModel.archivedRows.count == 2 }
        XCTAssertEqual(
            viewModel.archivedRows.map(\.id), [FakeGimClient.demoGroupChatId, FakeGimClient.demoDirectChatId])
        XCTAssertEqual(viewModel.rows, [])
        XCTAssertTrue(viewModel.hasArchived)
    }

    @MainActor
    func testActionErrorIsShownAndDismissed() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let summary = ChatSummary(
            chatId: "chat-gone", kind: .group, name: "Gone", avatar: nil, lastMessage: nil, unreadCount: 0,
            updatedAtMs: 0, memberCount: 2, state: .active)
        let gone = ChatRow(summary: summary, dateFormatter: makeFormatter())

        await viewModel.setPinned(gone, true)

        let expected = await ErrorPresenter.message(for: GimError.NotFound(reason: "chat chat-gone"), client: client)
        XCTAssertEqual(viewModel.actionErrorMessage, expected)
        XCTAssertNil(viewModel.errorMessage, "the list itself still loads")
        viewModel.dismissActionError()
        XCTAssertNil(viewModel.actionErrorMessage)

        await viewModel.mute(gone, .eightHours)
        XCTAssertNotNil(viewModel.actionErrorMessage)
        viewModel.dismissActionError()
        await viewModel.unmute(gone)
        XCTAssertNotNil(viewModel.actionErrorMessage)
        viewModel.dismissActionError()
        await viewModel.setArchived(gone, true)
        XCTAssertNotNil(viewModel.actionErrorMessage)
    }

    @MainActor
    private func lastMessageStatus(_ chatId: String, _ viewModel: ChatListViewModel) -> MessageStatus? {
        (try? row(chatId, viewModel)).flatMap { viewModel.lastMessageStatus(for: $0) }
    }

    @MainActor
    private func row(_ chatId: String, _ viewModel: ChatListViewModel) throws -> ChatRow {
        try XCTUnwrap(viewModel.rows.first { $0.id == chatId })
    }
}

/// Client whose chat list listener fails; the connection state listener works.
private final class FailingChatListClient: GimClientAPI {
    private let base = FakeGimClient()

    func session() async throws -> Session? { nil }
    func userId() -> String? { nil }
    func localStateReset() -> Bool { false }
    func createIdentity(displayName: String) async throws -> String { throw GimError.NotImplemented }
    func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws {}
    func startLink(hubs: [String]) throws -> any LinkSession { throw GimError.NotImplemented }
    func waitLink(link: any LinkSession) async throws -> String { throw GimError.NotImplemented }
    func confirmLink(accepted: Bool) async throws {}
    func approveLink(qrString: String) async throws -> any PendingApproval { throw GimError.NotRegistered }
    func confirmApproval(approval: any PendingApproval, accepted: Bool) async throws {}
    func devices() async throws -> [DeviceInfo] { throw GimError.NotRegistered }
    func userDevices(userId: String) async throws -> [DeviceInfo] { throw GimError.NotRegistered }
    func revokeDevice(deviceId: String) async throws {}
    func setDisplayName(name: String) async throws {}
    func claimHandle(handle: String) async throws {}
    func releaseHandle() async throws {}
    func signOut() async throws {}
    func startSync() async throws {}
    func stopSync() async throws {}
    func setNetworkReachable(reachable: Bool) {}
    func setLocalTimeZone(zone: (any LocalTimeZone)?) {}
    func findUser(handle: String) async throws -> UserProfile? { nil }
    func createDirectChat(userId: String) async throws -> String { throw GimError.NotRegistered }
    func createGroupChat(name: String, memberUserIds: [String]) async throws -> String {
        throw GimError.NotRegistered
    }
    func chatMembers(chatId: String) async throws -> [UserProfile] { throw GimError.NotRegistered }
    func addMembers(chatId: String, userIds: [String]) async throws {}
    func removeMember(chatId: String, userId: String) async throws {}
    func leaveChat(chatId: String) async throws {}
    func chatState(chatId: String) async throws -> ChatState { .active }
    func setGroupInfo(chatId: String, name: String?, avatarFilePath: String?) async throws {}
    func sendText(chatId: String, body: String, replyTo: String?) async throws -> String {
        throw GimError.NotRegistered
    }
    func sendMedia(
        chatId: String, filePath: String, mime: String, caption: String?, replyTo: String?
    ) async throws -> String {
        throw GimError.NotRegistered
    }
    func editMessage(chatId: String, messageId: String, newBody: String) async throws {}
    func deleteMessage(chatId: String, messageId: String) async throws {}
    func react(chatId: String, messageId: String, emoji: String) async throws {}
    func unreact(chatId: String, messageId: String, emoji: String) async throws {}
    func retrySend(chatId: String, messageId: String) async throws {}
    func cancelSend(chatId: String, messageId: String) async throws {}
    func markRead(chatId: String, upToMessageId: String) async throws {}
    func setTyping(chatId: String, active: Bool) async throws {}
    func stopTyping(chatId: String) async throws {}
    func fetchMedia(chatId: String, messageId: String, destPath: String) async throws -> String {
        throw GimError.NotFound(reason: "media")
    }
    func fetchThumbnail(chatId: String, messageId: String, destPath: String) async throws -> String? { nil }
    func chatList(listener: any ChatListListener) async throws -> TaskHandle { throw GimError.NotRegistered }
    func timeline(chatId: String) async throws -> any Timeline { throw GimError.NotRegistered }
    func connectionState(listener: any ConnectionStateListener) async throws -> TaskHandle {
        try await base.connectionState(listener: listener)
    }
    func typing(chatId: String, listener: any TypingListener) async throws -> TaskHandle {
        throw GimError.NotRegistered
    }

    func hubs() async throws -> [HubInfo] {
        throw GimError.NotRegistered
    }

    func addHub(url: String) async throws -> HubInfo {
        throw GimError.NotRegistered
    }

    func removeHub(hubId: String, confirmOwnedGroups: Bool) async throws {
        throw GimError.NotRegistered
    }

    func setPrimaryHub(hubId: String) async throws {
        throw GimError.NotRegistered
    }

    func hubList(listener: any HubListListener) async throws -> TaskHandle {
        throw GimError.NotRegistered
    }

    func registerPush(registration: PushRegistration) async throws {
        throw GimError.NotRegistered
    }

    func unregisterPush() async throws {
        throw GimError.NotRegistered
    }

    func processPush(payload: String) async throws -> NotificationContent {
        throw GimError.NotRegistered
    }

    func ownProfile() async throws -> UserProfile? {
        throw GimError.NotRegistered
    }

    func setAvatar(filePath: String, mime: String) async throws {
        throw GimError.NotRegistered
    }

    func removeAvatar() async throws {
        throw GimError.NotRegistered
    }

    func fetchUserAvatar(userId: String, destPath: String) async throws -> String {
        throw GimError.NotRegistered
    }

    func fetchChatAvatar(chatId: String, destPath: String) async throws -> String {
        throw GimError.NotRegistered
    }

    func privacy() async throws -> PrivacySettings {
        throw GimError.NotRegistered
    }

    func setReadReceipts(enabled: Bool) async throws {
        throw GimError.NotRegistered
    }

    func setTypingIndicators(enabled: Bool) async throws {
        throw GimError.NotRegistered
    }

    func blockUser(userId: String) async throws {
        throw GimError.NotRegistered
    }

    func unblockUser(userId: String) async throws {
        throw GimError.NotRegistered
    }

    func setChatMuted(chatId: String, mutedUntilMs: UInt64) async throws {
        throw GimError.NotRegistered
    }

    func setChatPinned(chatId: String, pinned: Bool) async throws {
        throw GimError.NotRegistered
    }

    func setChatArchived(chatId: String, archived: Bool) async throws {
        throw GimError.NotRegistered
    }

    func reportUser(userId: String, reason: ReportReason, note: String?, messageIds: [String]) async throws -> String {
        throw GimError.NotRegistered
    }

    func rotateRecoveryCode() async throws -> RecoveryRotation {
        throw GimError.NotRegistered
    }

    func deleteAccount() async throws -> [String] {
        throw GimError.NotRegistered
    }
}
