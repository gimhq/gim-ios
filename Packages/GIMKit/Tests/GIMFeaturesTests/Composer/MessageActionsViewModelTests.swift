import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class MessageActionsViewModelTests: XCTestCase {
    private let chatId = FakeGimClient.demoDirectChatId

    @MainActor
    private func makeClient() async -> RecordingClient {
        let (fake, _) = await connected(makeDemoClient())
        return RecordingClient(fake)
    }

    func testActionsPerMessage() {
        let media = MediaRef(chatId: chatId, messageId: "m", mime: "image/png", size: 1, hasThumbnail: false)
        XCTAssertEqual(
            MessageActionsViewModel.actions(for: makeMessage()), [.reply, .react, .copy, .edit, .delete])
        XCTAssertEqual(MessageActionsViewModel.actions(for: makeMessage(isOwn: false)), [.reply, .react, .copy])
        XCTAssertEqual(
            MessageActionsViewModel.actions(for: makeMessage(sendState: .failed(reason: "x"))),
            [.reply, .react, .copy, .edit, .delete, .retry])
        XCTAssertEqual(
            MessageActionsViewModel.actions(
                for: makeMessage(content: .image(media: media, width: nil, height: nil, caption: nil))),
            [.reply, .react, .delete])
        XCTAssertEqual(
            MessageActionsViewModel.actions(
                for: makeMessage(isOwn: false, content: .file(media: media, fileName: "a.pdf", caption: "Look"))),
            [.reply, .react, .copy])
        XCTAssertEqual(MessageActionsViewModel.actions(for: makeMessage(content: .deleted)), [])
        XCTAssertEqual(MessageActionsViewModel.quickReactions.count, 6)
    }

    @MainActor
    func testToggleReaction() async {
        let client = await makeClient()
        let viewModel = MessageActionsViewModel(client: client, chatId: chatId)
        let messageId = try! await client.fake.sendText(chatId: chatId, body: "Hi", replyTo: nil)

        await viewModel.toggleReaction("👍", on: makeMessage(id: messageId))
        await viewModel.toggleReaction(
            "👍", on: makeMessage(id: messageId, reactions: [ReactionGroup(emoji: "👍", count: 1, own: true)]))
        await viewModel.toggleReaction(
            "❤️", on: makeMessage(id: messageId, reactions: [ReactionGroup(emoji: "❤️", count: 2, own: false)]))

        let calls = await client.calls
        XCTAssertEqual(
            calls,
            [
                .react(messageId: messageId, emoji: "👍"), .unreact(messageId: messageId, emoji: "👍"),
                .react(messageId: messageId, emoji: "❤️"),
            ])
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testDeleteNeedsConfirmation() async {
        let client = await makeClient()
        let viewModel = MessageActionsViewModel(client: client, chatId: chatId)
        let messageId = try! await client.fake.sendText(chatId: chatId, body: "Hi", replyTo: nil)

        viewModel.requestDelete(makeMessage(id: "other", isOwn: false))
        XCTAssertNil(viewModel.pendingDelete, "only own messages")

        viewModel.requestDelete(makeMessage(id: messageId))
        XCTAssertEqual(viewModel.pendingDelete?.messageId, messageId)
        viewModel.cancelDelete()
        XCTAssertNil(viewModel.pendingDelete)
        var calls = await client.calls
        XCTAssertEqual(calls, [])

        viewModel.requestDelete(makeMessage(id: messageId))
        await viewModel.delete(makeMessage(id: messageId))
        calls = await client.calls
        XCTAssertEqual(calls, [.delete(messageId: messageId)])
        XCTAssertNil(viewModel.pendingDelete)
    }

    @MainActor
    func testDeleteUnsentCancelsSend() async {
        let client = await makeClient()
        let viewModel = MessageActionsViewModel(client: client, chatId: chatId)
        let messageId = try! await client.fake.sendText(chatId: chatId, body: "Hi", replyTo: nil)

        await viewModel.delete(makeMessage(id: messageId, sendState: .pending))

        let calls = await client.calls
        XCTAssertEqual(calls, [.cancelSend(messageId: messageId)])
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testErrorsAreShown() async {
        let client = await makeClient()
        let viewModel = MessageActionsViewModel(client: client, chatId: chatId)
        await client.failNext(with: .Network(reason: "down"))
        await viewModel.toggleReaction("👍", on: makeMessage())
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.Network(reason: "down")))
        viewModel.dismissError()

        await viewModel.delete(makeMessage(id: "missing"))
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
