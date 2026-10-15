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
}

/// Client whose chat list listener fails; the connection state listener works.
private final class FailingChatListClient: GimClientAPI {
    private let base = FakeGimClient()

    func session() async throws -> Session? { nil }
    func register(handle: String, displayName: String) async throws -> Session { throw GimError.NotRegistered }
    func signOut() async throws {}
    func startSync() async throws {}
    func stopSync() async throws {}
    func setNetworkReachable(reachable: Bool) {}
    func findUser(handle: String) async throws -> UserProfile? { nil }
    func createDirectChat(userId: String) async throws -> String { throw GimError.NotRegistered }
    func createGroupChat(name: String, memberUserIds: [String]) async throws -> String {
        throw GimError.NotRegistered
    }
    func chatMembers(chatId: String) async throws -> [UserProfile] { throw GimError.NotRegistered }
    func addMembers(chatId: String, userIds: [String]) async throws {}
    func removeMember(chatId: String, userId: String) async throws {}
    func leaveChat(chatId: String) async throws {}
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
