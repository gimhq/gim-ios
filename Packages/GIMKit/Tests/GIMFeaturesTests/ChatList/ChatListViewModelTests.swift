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
        let (client, _) = makeDemoClient()
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
        await eventually { viewModel.connectionState == .online }
    }

    @MainActor
    func testNewMessageReordersViaRemoveAndInsert() async throws {
        let (client, _) = makeDemoClient()
        let viewModel = await startedViewModel(client)

        try await client.receiveText(FakeGimClient.demoDirectChatId, from: "user-sofia", text: "On my way")

        await eventually { viewModel.rows.first?.id == FakeGimClient.demoDirectChatId }
        XCTAssertEqual(viewModel.rows.map(\.id), [FakeGimClient.demoDirectChatId, FakeGimClient.demoGroupChatId])
        XCTAssertEqual(viewModel.rows[0].preview, "On my way")
        XCTAssertEqual(viewModel.rows[0].unreadText, "3")
    }

    @MainActor
    func testUpdateInPlaceAndDeletedPreview() async throws {
        let (client, _) = makeDemoClient()
        let viewModel = await startedViewModel(client)

        try await client.markRead(FakeGimClient.demoGroupChatId)
        await eventually { viewModel.rows[0].unreadText == nil }

        let id = try await client.sendText(FakeGimClient.demoGroupChatId, text: "Wrong chat", replyTo: nil)
        try await client.delete(id)
        await eventually { viewModel.rows[0].preview == "Alex Morgan: Message deleted" }
    }

    @MainActor
    func testNewChatIsInserted() async throws {
        let (client, _) = makeDemoClient()
        let viewModel = await startedViewModel(client)

        let chatId = try await client.createGroupChat(name: "Regatta", members: ["user-sofia", "user-luca"])

        await eventually { viewModel.rows.count == 3 }
        XCTAssertEqual(viewModel.rows.first?.id, chatId)
        XCTAssertNil(viewModel.rows.first?.preview)
    }

    @MainActor
    func testConnectionStateFollowsClient() async {
        let (client, scheduler) = makeDemoClient()
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.connectionState == .online }

        await client.setNetworkAvailable(false)
        await eventually { viewModel.connectionState == .offline }

        await client.setNetworkAvailable(true)
        await eventually { viewModel.connectionState == .connecting }
        await scheduler.runUntilIdle()
        await eventually { viewModel.connectionState == .online }
    }

    @MainActor
    func testStopUnsubscribes() async throws {
        let (client, _) = makeDemoClient()
        let viewModel = await startedViewModel(client)

        viewModel.stop()
        await settle()
        try await client.markRead(FakeGimClient.demoGroupChatId)
        await settle()

        XCTAssertEqual(viewModel.rows[0].unreadText, "3")
    }

    @MainActor
    func testRefreshResubscribesWithReset() async throws {
        let (client, _) = makeDemoClient()
        let viewModel = await startedViewModel(client)
        viewModel.stop()
        await settle()
        try await client.markRead(FakeGimClient.demoGroupChatId)

        viewModel.refresh()

        await eventually { viewModel.rows[0].unreadText == nil }
        try await client.receiveText(FakeGimClient.demoGroupChatId, from: "user-luca", text: "Anchor's up")
        await eventually { viewModel.rows[0].preview == "Luca Bianchi: Anchor's up" }
    }

    @MainActor
    func testSubscribeFailureShowsError() async {
        let client = FailingChatListClient()
        let viewModel = ChatListViewModel(client: client, dateFormatter: makeFormatter())

        viewModel.start()

        await eventually { viewModel.errorMessage != nil }
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.unauthorized))
    }
}

/// Client whose chat list subscription fails; the connection subscription works.
private final class FailingChatListClient: GimClientAPI {
    private let base = FakeGimClient()

    func loginState() async throws -> LoginState { .unregistered }
    func register(serverUrl: String, handle: String, displayName: String) async throws -> Session {
        throw GimError.unauthorized
    }
    func logout() async throws {}
    func findUser(handle: String) async throws -> UserProfile? { nil }
    func createDirectChat(with user: UserId) async throws -> ChatId { throw GimError.unauthorized }
    func createGroupChat(name: String, members: [UserId]) async throws -> ChatId { throw GimError.unauthorized }
    func chatDetails(_ chatId: ChatId) async throws -> ChatDetails { throw GimError.unauthorized }
    func addMember(_ chatId: ChatId, user: UserId) async throws {}
    func removeMember(_ chatId: ChatId, user: UserId) async throws {}
    func sendText(_ chatId: ChatId, text: String, replyTo: MessageId?) async throws -> MessageId {
        throw GimError.unauthorized
    }
    func sendMedia(
        _ chatId: ChatId, filePath: String, mime: String, kind: MediaKind, caption: String?, replyTo: MessageId?,
        width: UInt32?, height: UInt32?
    ) async throws -> MessageId {
        throw GimError.unauthorized
    }
    func edit(_ messageId: MessageId, text: String) async throws {}
    func delete(_ messageId: MessageId) async throws {}
    func react(_ messageId: MessageId, emoji: String, remove: Bool) async throws {}
    func retry(_ messageId: MessageId) async throws {}
    func markRead(_ chatId: ChatId) async throws {}
    func setTyping(_ chatId: ChatId, typing: Bool) async throws {}
    func loadOlder(_ chatId: ChatId, count: UInt32) async throws -> Bool { false }
    func fetchMedia(_ mediaId: MediaId) async throws -> String { throw GimError.notFound }
    func setNetworkAvailable(_ available: Bool) async {}
    func subscribeChatList(_ listener: any ChatListListener) async throws -> any SubscriptionHandle {
        throw GimError.unauthorized
    }
    func subscribeTimeline(_ chatId: ChatId, _ listener: any TimelineListener) async throws -> any SubscriptionHandle {
        throw GimError.unauthorized
    }
    func subscribeConnection(_ listener: any ConnectionListener) async throws -> any SubscriptionHandle {
        try await base.subscribeConnection(listener)
    }
    func subscribeTyping(_ chatId: ChatId, _ listener: any TypingListener) async throws -> any SubscriptionHandle {
        throw GimError.unauthorized
    }
}
