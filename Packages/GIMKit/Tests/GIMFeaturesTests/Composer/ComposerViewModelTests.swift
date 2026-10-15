import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class ComposerViewModelTests: XCTestCase {
    private let chatId = FakeGimClient.demoDirectChatId

    @MainActor
    private func makeClient() async -> RecordingClient {
        let (fake, _) = await connected(makeDemoClient())
        return RecordingClient(fake)
    }

    @MainActor
    private func makeViewModel(
        _ client: RecordingClient, clock: TestClock = TestClock(), drafts: ComposerDrafts = ComposerDrafts()
    ) -> ComposerViewModel {
        ComposerViewModel(client: client, chatId: chatId, drafts: drafts, now: { clock.now })
    }

    /// Waits for the queued typing calls to reach the client.
    @MainActor
    private func typingCalls(_ client: RecordingClient, count: Int) async -> [Bool] {
        for _ in 0..<1_000 {
            let calls = await client.typingCalls
            if calls.count >= count { return calls }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return await client.typingCalls
    }

    // MARK: - Enable rules

    @MainActor
    func testSendEnabledOnlyForNonBlankText() async {
        let viewModel = makeViewModel(await makeClient())
        XCTAssertFalse(viewModel.canSend)
        viewModel.textChanged("  \n\t ")
        XCTAssertFalse(viewModel.canSend)
        viewModel.textChanged(" hi ")
        XCTAssertTrue(viewModel.canSend)
        viewModel.textChanged("")
        XCTAssertFalse(viewModel.canSend)
    }

    @MainActor
    func testBlankSendDoesNothing() async {
        let client = await makeClient()
        let viewModel = makeViewModel(client)
        viewModel.textChanged("   ")
        await viewModel.send()
        let calls = await client.calls
        XCTAssertFalse(calls.contains { if case .sendText = $0 { true } else { false } })
    }

    @MainActor
    func testDraftIsKeptPerChat() async {
        let client = await makeClient()
        let drafts = ComposerDrafts()
        let first = makeViewModel(client, drafts: drafts)
        first.textChanged("unfinished")
        XCTAssertEqual(makeViewModel(client, drafts: drafts).text, "unfinished")
        XCTAssertEqual(
            ComposerViewModel(client: client, chatId: FakeGimClient.demoGroupChatId, drafts: drafts).text, "")
    }

    // MARK: - Sending and reply

    @MainActor
    func testSendTrimsAndRepliesThenClears() async {
        let client = await makeClient()
        let drafts = ComposerDrafts()
        let viewModel = makeViewModel(client, drafts: drafts)
        let targetId = try! await client.fake.sendText(chatId: chatId, body: "Earlier", replyTo: nil)
        viewModel.setReplyTarget(makeMessage(id: targetId))
        viewModel.textChanged("  Hello there \n")

        await viewModel.send()

        XCTAssertNil(viewModel.errorMessage)
        let calls = await client.calls
        XCTAssertTrue(calls.contains(.sendText(body: "Hello there", replyTo: targetId)))
        XCTAssertEqual(viewModel.text, "")
        XCTAssertNil(viewModel.replyTarget)
        XCTAssertFalse(viewModel.isSending)
        XCTAssertEqual(drafts[chatId], "")
    }

    @MainActor
    func testSendFailureKeepsTextAndReplyAndShowsError() async {
        let client = await makeClient()
        let viewModel = makeViewModel(client)
        viewModel.setReplyTarget(makeMessage(id: "target", isOwn: false))
        viewModel.textChanged("Hello")
        await client.failNext(with: .Network(reason: "down"))

        await viewModel.send()

        XCTAssertEqual(viewModel.text, "Hello")
        XCTAssertEqual(viewModel.replyTarget?.messageId, "target")
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.Network(reason: "down")))
        viewModel.dismissError()
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Edit

    @MainActor
    func testEditPrefillsSendsEditAndRestoresDraft() async {
        let client = await makeClient()
        let messageId = try! await client.fake.sendText(chatId: chatId, body: "Original", replyTo: nil)
        let viewModel = makeViewModel(client)
        viewModel.setReplyTarget(makeMessage(id: "target", isOwn: false))
        viewModel.textChanged("draft")

        viewModel.beginEdit(makeMessage(id: messageId, content: .text(body: "Original")))
        XCTAssertEqual(viewModel.text, "Original")
        XCTAssertEqual(viewModel.editTarget?.messageId, messageId)
        XCTAssertNil(viewModel.replyTarget, "editing ends the reply")
        XCTAssertFalse(viewModel.canAttach)

        viewModel.textChanged("Changed")
        await viewModel.send()

        let calls = await client.calls
        XCTAssertTrue(calls.contains(.edit(messageId: messageId, newBody: "Changed")))
        XCTAssertFalse(calls.contains { if case .sendText = $0 { true } else { false } })
        XCTAssertNil(viewModel.editTarget)
        XCTAssertEqual(viewModel.text, "draft")
    }

    @MainActor
    func testUnchangedEditSkipsClient() async {
        let client = await makeClient()
        let viewModel = makeViewModel(client)
        viewModel.beginEdit(makeMessage(content: .text(body: "Same")))
        await viewModel.send()
        let calls = await client.calls
        XCTAssertFalse(calls.contains { if case .edit = $0 { true } else { false } })
        XCTAssertNil(viewModel.editTarget)
    }

    @MainActor
    func testCancelEditRestoresDraftAndReplyEndsEdit() async {
        let viewModel = makeViewModel(await makeClient())
        viewModel.textChanged("draft")
        viewModel.beginEdit(makeMessage(content: .text(body: "Old")))
        viewModel.cancelEdit()
        XCTAssertNil(viewModel.editTarget)
        XCTAssertEqual(viewModel.text, "draft")

        viewModel.beginEdit(makeMessage(content: .text(body: "Old")))
        viewModel.setReplyTarget(makeMessage(id: "other", isOwn: false))
        XCTAssertNil(viewModel.editTarget)
        XCTAssertEqual(viewModel.replyTarget?.messageId, "other")
        XCTAssertEqual(viewModel.text, "draft")
    }

    @MainActor
    func testEditIgnoredForOthersDeletedAndMedia() async {
        let viewModel = makeViewModel(await makeClient())
        let media = MediaRef(chatId: chatId, messageId: "m", mime: "image/png", size: 1, hasThumbnail: false)
        for message in [
            makeMessage(isOwn: false),
            makeMessage(content: .deleted),
            makeMessage(content: .image(media: media, width: nil, height: nil, caption: nil)),
        ] {
            viewModel.beginEdit(message)
            XCTAssertNil(viewModel.editTarget)
        }
    }

    @MainActor
    func testClearDropsEverything() async {
        let drafts = ComposerDrafts()
        let viewModel = makeViewModel(await makeClient(), drafts: drafts)
        viewModel.textChanged("text")
        viewModel.setReplyTarget(makeMessage(isOwn: false))
        viewModel.clear()
        XCTAssertEqual(viewModel.text, "")
        XCTAssertNil(viewModel.replyTarget)
        XCTAssertEqual(drafts[chatId], "")
    }

    // MARK: - Typing

    @MainActor
    func testTypingIsThrottledToOncePerInterval() async {
        let client = await makeClient()
        let clock = TestClock()
        let viewModel = makeViewModel(client, clock: clock)

        viewModel.textChanged("h")
        clock.advance(by: 1)
        viewModel.textChanged("he")
        clock.advance(by: 2.9)
        viewModel.textChanged("hel")
        let beforeInterval = await typingCalls(client, count: 1)
        XCTAssertEqual(beforeInterval, [true])

        clock.advance(by: 0.1)
        viewModel.textChanged("hell")
        await settle()
        let afterInterval = await typingCalls(client, count: 2)
        XCTAssertEqual(afterInterval, [true, true])
    }

    @MainActor
    func testTypingStopsWhenClearedSentOrDisappearing() async {
        let client = await makeClient()
        let clock = TestClock()
        let viewModel = makeViewModel(client, clock: clock)

        viewModel.textChanged("a")
        viewModel.textChanged("")
        let afterClear = await typingCalls(client, count: 2)
        XCTAssertEqual(afterClear, [true, false])

        viewModel.textChanged("b")
        await viewModel.send()
        let afterSend = await typingCalls(client, count: 4)
        XCTAssertEqual(afterSend, [true, false, true, false])

        viewModel.textChanged("c")
        viewModel.disappear()
        let afterDisappear = await typingCalls(client, count: 6)
        XCTAssertEqual(afterDisappear, [true, false, true, false, true, false])

        viewModel.disappear()
        viewModel.clear()
        await settle()
        let count = await client.typingCalls.count
        XCTAssertEqual(count, 6, "no stop without a start")
    }

    @MainActor
    func testEditingDoesNotSendTyping() async {
        let client = await makeClient()
        let viewModel = makeViewModel(client)
        viewModel.beginEdit(makeMessage(content: .text(body: "Old")))
        viewModel.textChanged("New text")
        await settle()
        let calls = await client.typingCalls
        XCTAssertEqual(calls, [])
    }

    // MARK: - Attachments

    @MainActor
    func testSendAttachmentUsesMimeAndReply() async throws {
        let client = await makeClient()
        let viewModel = makeViewModel(client)
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = directory + "/report.PDF"
        try Data("pdf".utf8).write(to: URL(fileURLWithPath: path))
        let targetId = try await client.fake.sendText(chatId: chatId, body: "Earlier", replyTo: nil)
        viewModel.setReplyTarget(makeMessage(id: targetId))

        let sent = await viewModel.sendAttachment(atPath: path)

        XCTAssertTrue(sent)
        XCTAssertNil(viewModel.errorMessage)
        let calls = await client.calls
        XCTAssertTrue(calls.contains(.sendMedia(mime: "application/pdf", replyTo: targetId)))
        XCTAssertNil(viewModel.replyTarget)
    }

    @MainActor
    func testSendAttachmentErrors() async {
        let client = await makeClient()
        let viewModel = makeViewModel(client)

        let sent = await viewModel.sendAttachment(atPath: makeTemporaryDirectory() + "/missing.jpg")
        XCTAssertFalse(sent)
        XCTAssertEqual(viewModel.errorMessage, MediaPreparationError.unreadable.message)

        viewModel.attachmentFailed(MediaPreparationError.tooLarge(byteCount: 1))
        XCTAssertEqual(viewModel.errorMessage, MediaPreparationError.tooLarge(byteCount: 1).message)
        let calls = await client.calls
        XCTAssertFalse(calls.contains { if case .sendMedia = $0 { true } else { false } })
    }

    func testPreviewText() {
        let media = MediaRef(chatId: chatId, messageId: "m", mime: "image/png", size: 1, hasThumbnail: false)
        func preview(_ content: MessageContent) -> String {
            ComposerViewModel.previewText(for: makeMessage(content: content))
        }
        XCTAssertEqual(preview(.text(body: "Hi")), "Hi")
        XCTAssertEqual(preview(.image(media: media, width: nil, height: nil, caption: nil)), "Photo")
        XCTAssertEqual(preview(.image(media: media, width: nil, height: nil, caption: "Sunset")), "Sunset")
        XCTAssertEqual(preview(.file(media: media, fileName: "a.pdf", caption: "")), "a.pdf")
        XCTAssertEqual(preview(.file(media: media, fileName: nil, caption: nil)), "File")
        XCTAssertEqual(preview(.deleted), "This message was deleted")
    }
}
