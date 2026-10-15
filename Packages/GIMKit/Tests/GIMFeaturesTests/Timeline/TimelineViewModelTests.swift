import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class TimelineViewModelTests: XCTestCase {
    @MainActor
    private func startedViewModel(_ client: FakeGimClient, chatId: String) async -> TimelineViewModel {
        let viewModel = TimelineViewModel(
            client: client, chatId: chatId, mediaDirectory: makeTemporaryDirectory(), pageSize: 30)
        XCTAssertTrue(viewModel.isLoading)
        viewModel.start()
        await eventually { !viewModel.isLoading && !viewModel.title.isEmpty }
        return viewModel
    }

    @MainActor
    private func messageCount(_ viewModel: TimelineViewModel) -> Int {
        viewModel.items.filter { $0.messageRow != nil }.count
    }

    @MainActor
    private func status(_ viewModel: TimelineViewModel, _ messageId: String) -> MessageStatus? {
        viewModel.items.first { $0.id == TimelineDisplayItem.id(forMessage: messageId) }?.messageRow?.status
    }

    @MainActor
    func testInitialLoad() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: FakeGimClient.demoDirectChatId)

        XCTAssertEqual(viewModel.title, "Sofia Marin")
        XCTAssertFalse(viewModel.isGroup)
        XCTAssertEqual(messageCount(viewModel), FakeGimClient.initialWindow)
        XCTAssertTrue(viewModel.lastChange.isReset)
        XCTAssertTrue(viewModel.items.first?.id.hasPrefix("day:") ?? false)
        XCTAssertTrue(viewModel.items.compactMap(\.messageRow).allSatisfy { $0.senderName == nil })
        XCTAssertNil(viewModel.typingText)
    }

    @MainActor
    func testLoadOlderIsGuardedAndTracksHasMore() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: FakeGimClient.demoDirectChatId)
        var changes: [TimelineChangeSet] = []
        viewModel.onChange = { changes.append($0) }

        let first = Task { await viewModel.loadOlder() }
        let second = Task { await viewModel.loadOlder() }
        await first.value
        await second.value

        await eventually { self.messageCount(viewModel) == 80 }
        await settle()
        XCTAssertEqual(messageCount(viewModel), 80, "the concurrent call must not load a second page")
        XCTAssertTrue(viewModel.hasMore)
        XCTAssertFalse(viewModel.isLoadingOlder)
        XCTAssertEqual(changes.count, 1)
        XCTAssertTrue(changes.first?.isPrepend ?? false)
        XCTAssertEqual(changes.first?.insertedIds.filter { $0.hasPrefix("msg:") }.count, 30)

        while viewModel.hasMore {
            await viewModel.loadOlder()
        }
        await eventually { self.messageCount(viewModel) == FakeGimClient.demoDirectMessageCount }
        await viewModel.loadOlder()
        await settle()
        XCTAssertEqual(messageCount(viewModel), FakeGimClient.demoDirectMessageCount)
    }

    @MainActor
    func testLiveInsertAtBottom() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: FakeGimClient.demoDirectChatId)

        let messageId = try await client.receiveText(
            chatId: FakeGimClient.demoDirectChatId, from: "user-sofia", body: "Anchored in Poros")

        await eventually { viewModel.items.last?.id == TimelineDisplayItem.id(forMessage: messageId) }
        XCTAssertFalse(viewModel.lastChange.isPrepend)
        XCTAssertFalse(viewModel.lastChange.isReset)
        XCTAssertTrue(viewModel.lastChange.insertedIds.contains(TimelineDisplayItem.id(forMessage: messageId)))
        XCTAssertEqual(viewModel.items.last?.messageRow?.body, .text("Anchored in Poros"))
    }

    @MainActor
    func testOwnMessageStatusProgression() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: FakeGimClient.demoDirectChatId)

        let messageId = try await client.sendText(chatId: FakeGimClient.demoDirectChatId, body: "Ready", replyTo: nil)
        await eventually { self.status(viewModel, messageId) == .sending }

        await scheduler.advance(by: .milliseconds(300))
        await eventually { self.status(viewModel, messageId) == .sent }
        await scheduler.advance(by: .milliseconds(700))
        await eventually { self.status(viewModel, messageId) == .delivered }
        await scheduler.advance(by: .milliseconds(1500))
        await eventually { self.status(viewModel, messageId) == .read }
        XCTAssertEqual(viewModel.lastChange.reloadedIds, [TimelineDisplayItem.id(forMessage: messageId)])
    }

    @MainActor
    func testRetryFailedMessage() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: FakeGimClient.demoDirectChatId)
        await client.failNextSends(1)

        let messageId = try await client.sendText(chatId: FakeGimClient.demoDirectChatId, body: "Ready", replyTo: nil)
        await scheduler.advance(by: .milliseconds(300))
        await eventually { self.status(viewModel, messageId) == .failed(reason: FakeGimClient.failureReason) }

        await viewModel.retry(messageId: messageId)
        await eventually { self.status(viewModel, messageId) == .sending }
        await scheduler.advance(by: .milliseconds(300))
        await eventually { self.status(viewModel, messageId) == .sent }
        XCTAssertNil(viewModel.errorMessage)

        await viewModel.retry(messageId: messageId)
        XCTAssertNotNil(viewModel.errorMessage, "only failed messages can be retried")
    }

    @MainActor
    func testMarkReadConditions() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: FakeGimClient.demoDirectChatId)
        let newest = try XCTUnwrap(viewModel.items.last?.messageRow?.message)
        XCTAssertFalse(newest.isOwn)

        await viewModel.markReadIfNeeded(bottomVisible: false, appActive: true)
        XCTAssertNil(viewModel.markedReadUpTo)
        await viewModel.markReadIfNeeded(bottomVisible: true, appActive: false)
        XCTAssertNil(viewModel.markedReadUpTo)
        try await Self.assertUnread(client, 2)

        await viewModel.markReadIfNeeded(bottomVisible: true, appActive: true)
        XCTAssertEqual(viewModel.markedReadUpTo, newest.messageId)
        try await Self.assertUnread(client, 0)

        let incoming = try await client.receiveText(
            chatId: FakeGimClient.demoDirectChatId, from: "user-sofia", body: "One more")
        await eventually { viewModel.items.last?.id == TimelineDisplayItem.id(forMessage: incoming) }
        try await Self.assertUnread(client, 1)
        await viewModel.markReadIfNeeded(bottomVisible: true, appActive: true)
        XCTAssertEqual(viewModel.markedReadUpTo, incoming)
        try await Self.assertUnread(client, 0)
    }

    private static func assertUnread(
        _ client: FakeGimClient, _ expected: UInt32, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let diffs = await first(try await ListenerBridge.chatList(client))
        guard case .reset(let summaries) = diffs?.first else {
            return XCTFail("expected a reset", file: file, line: line)
        }
        let direct = summaries.first { $0.chatId == FakeGimClient.demoDirectChatId }
        XCTAssertEqual(direct?.unreadCount, expected, file: file, line: line)
    }

    @MainActor
    func testGroupSenderNamesAndTypingText() async throws {
        let (client, _) = await connected(makeDemoClient())
        let chatId = FakeGimClient.demoGroupChatId
        let viewModel = await startedViewModel(client, chatId: chatId)
        await eventually { viewModel.isGroup }
        XCTAssertEqual(viewModel.title, "Aegean Crew")
        XCTAssertTrue(viewModel.items.compactMap(\.messageRow).contains { $0.senderName == "Luca Bianchi" })

        try await client.setPeerTyping(chatId: chatId, userId: "user-sofia", active: true)
        await eventually { viewModel.typingText == "Sofia Marin is typing…" }
        XCTAssertEqual(viewModel.items.last?.kind, .typing("Sofia Marin is typing…"))
        XCTAssertEqual(viewModel.lastChange.insertedIds, [TimelineDisplayItem.typingId])

        try await client.setPeerTyping(chatId: chatId, userId: "user-luca", active: true)
        await eventually { viewModel.typingText == "Sofia Marin and Luca Bianchi are typing…" }
        XCTAssertEqual(viewModel.lastChange.reloadedIds, [TimelineDisplayItem.typingId])

        try await client.setPeerTyping(chatId: chatId, userId: "user-nikos", active: true)
        await eventually { viewModel.typingText == "3 people are typing…" }

        for userId in ["user-sofia", "user-luca", "user-nikos"] {
            try await client.setPeerTyping(chatId: chatId, userId: userId, active: false)
        }
        await eventually { viewModel.typingText == nil }
        XCTAssertNotEqual(viewModel.items.last?.id, TimelineDisplayItem.typingId)
        XCTAssertEqual(viewModel.lastChange.deletedIds, [TimelineDisplayItem.typingId])
    }

    @MainActor
    func testMediaFilesAreFetchedOnce() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client, chatId: FakeGimClient.demoDirectChatId)
        let fileRow = try XCTUnwrap(
            viewModel.items.compactMap(\.messageRow).first {
                if case .file = $0.body { true } else { false }
            })
        guard case .file(let media, let fileName, _, _) = fileRow.body else { return XCTFail("expected a file") }
        let noThumbnail = await viewModel.thumbnailPath(for: media)
        XCTAssertNil(noThumbnail)

        let path = try await viewModel.mediaFilePath(for: media, fileName: fileName)
        XCTAssertTrue(path.hasSuffix("/crew-list.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let again = try await viewModel.mediaFilePath(for: media, fileName: fileName)
        XCTAssertEqual(again, path)

        let imageRow = try XCTUnwrap(
            viewModel.items.compactMap(\.messageRow).first {
                if case .image = $0.body { true } else { false }
            })
        guard case .image(let image, _, _, _) = imageRow.body else { return XCTFail("expected an image") }
        let thumbnail = await viewModel.thumbnailPath(for: image)
        XCTAssertNotNil(thumbnail)
    }
}
