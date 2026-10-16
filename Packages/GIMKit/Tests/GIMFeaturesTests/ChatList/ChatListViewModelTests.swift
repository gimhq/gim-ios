import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class ChatListViewModelTests: XCTestCase {
    @MainActor
    private func startedViewModel(_ client: FakeGimClient) async -> ChatListViewModel {
        let viewModel = ChatListViewModel(client: client, dateFormatter: makeFormatter())
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
}
