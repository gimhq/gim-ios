import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class ChatActionsViewModelTests: XCTestCase {
    private let direct = FakeGimClient.demoDirectChatId
    private let group = FakeGimClient.demoGroupChatId

    @MainActor
    private func startedViewModel(_ client: any GimClientAPI, chatId: String) async -> ChatActionsViewModel {
        let viewModel = ChatActionsViewModel(client: client, chatId: chatId, now: { fixedNow })
        viewModel.start()
        await eventually { viewModel.peerName != nil || viewModel.isGroup }
        return viewModel
    }

    @MainActor
    func testStateMirrorsTheDirectChatSummary() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = ChatActionsViewModel(client: client, chatId: direct, now: { fixedNow })
        XCTAssertFalse(viewModel.canBlock, "nothing is known before the chat list arrives")
        XCTAssertNil(viewModel.peerName)

        viewModel.start()
        await eventually { viewModel.peerName != nil }

        XCTAssertEqual(viewModel.chatId, direct)
        XCTAssertFalse(viewModel.isGroup)
        XCTAssertFalse(viewModel.isPinned)
        XCTAssertFalse(viewModel.isMuted)
        XCTAssertFalse(viewModel.isArchived)
        XCTAssertFalse(viewModel.isBlocked)
        XCTAssertEqual(viewModel.peerName, "Sofia Marin")
        XCTAssertTrue(viewModel.canBlock)
        XCTAssertNil(viewModel.errorMessage)
        viewModel.stop()
    }

    @MainActor
    func testGroupChatCannotBeBlocked() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: group)

        XCTAssertTrue(viewModel.isGroup)
        XCTAssertNil(viewModel.peerName)
        XCTAssertFalse(viewModel.canBlock)
        XCTAssertFalse(viewModel.isBlocked)
    }

    @MainActor
    func testPinAndUnpin() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: direct)

        await viewModel.setPinned(true)
        await eventually { viewModel.isPinned }

        await viewModel.setPinned(false)
        await eventually { !viewModel.isPinned }
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testMuteAndUnmute() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: group)

        await viewModel.mute(.oneHour)
        await eventually { viewModel.isMuted }

        await viewModel.unmute()
        await eventually { !viewModel.isMuted }

        await viewModel.mute(.always)
        await eventually { viewModel.isMuted }
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testAnExpiredMuteIsNotMuted() async throws {
        let (client, _) = await connected(makeDemoClient())
        try await client.setChatMuted(chatId: group, mutedUntilMs: fixedNow.epochMilliseconds - 1)
        let viewModel = await startedViewModel(client, chatId: group)

        XCTAssertFalse(viewModel.isMuted)
    }

    @MainActor
    func testArchiveAndUnarchive() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: group)

        await viewModel.setArchived(true)
        await eventually { viewModel.isArchived }
        XCTAssertTrue(viewModel.isGroup, "the summary is still tracked while archived")

        await viewModel.setArchived(false)
        await eventually { !viewModel.isArchived }
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testBlockAndUnblockThePeer() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: direct)

        await viewModel.block()
        await eventually { viewModel.isBlocked }
        let blocked = try await client.privacy()
        XCTAssertEqual(blocked.blockedUserIds, ["user-sofia"])
        XCTAssertTrue(viewModel.canBlock, "a blocked peer can be unblocked")

        await viewModel.unblock()
        await eventually { !viewModel.isBlocked }
        let unblocked = try await client.privacy()
        XCTAssertEqual(unblocked.blockedUserIds, [])
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testBlockingInGroupChatDoesNothing() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: group)

        await viewModel.block()

        let privacy = try await client.privacy()
        XCTAssertEqual(privacy.blockedUserIds, [])
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testErrorsAreSurfacedAndDismissed() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = ChatActionsViewModel(client: client, chatId: "chat-gone", now: { fixedNow })
        viewModel.start()

        await viewModel.setPinned(true)

        let expected = await ErrorPresenter.message(for: GimError.NotFound(reason: "chat chat-gone"), client: client)
        XCTAssertEqual(viewModel.errorMessage, expected)
        viewModel.dismissError()
        XCTAssertNil(viewModel.errorMessage)

        await viewModel.mute(.eightHours)
        XCTAssertNotNil(viewModel.errorMessage)
        viewModel.dismissError()
        await viewModel.unmute()
        XCTAssertNotNil(viewModel.errorMessage)
        viewModel.dismissError()
        await viewModel.setArchived(true)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    @MainActor
    func testBlockErrorIsSurfaced() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: direct)
        // Signing out empties the chat list; the last known peer is kept.
        try await client.signOut()
        await settle()

        await viewModel.block()

        let expected = await ErrorPresenter.message(for: GimError.NotRegistered, client: client)
        XCTAssertEqual(viewModel.errorMessage, expected)
        viewModel.dismissError()
        await viewModel.unblock()
        XCTAssertEqual(viewModel.errorMessage, expected)
    }
}
