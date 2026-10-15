import Foundation
import GIMClientKit
import GIMFeatures
import Observation
import XCTest

final class ListenerBridgeTests: XCTestCase {
    func testChatListStreamStartsWithResetAndFollowsChanges() async throws {
        let (client, _) = await connected(makeDemoClient())
        let stream = try await ListenerBridge.chatList(client)
        var iterator = stream.makeAsyncIterator()

        var list: [ChatSummary] = []
        let first = await iterator.next()
        let reset = try DiffApplier.apply(try XCTUnwrap(first), to: &list)
        XCTAssertTrue(reset.isReset)
        XCTAssertEqual(list.count, 2)

        try await client.markRead(chatId: FakeGimClient.demoDirectChatId, upToMessageId: "msg-sofia-149")
        let second = await iterator.next()
        let changes = try DiffApplier.apply(try XCTUnwrap(second), to: &list)
        XCTAssertEqual(changes.reloads, [1])
        XCTAssertEqual(list[1].unreadCount, 0)
    }

    func testTimelineStreamDeliversStatusProgression() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let stream = try await ListenerBridge.timeline(client, chatId: FakeGimClient.demoDirectChatId)
        var iterator = stream.makeAsyncIterator()
        var items: [TimelineItem] = []
        let reset = await iterator.next()
        try DiffApplier.apply(try XCTUnwrap(reset), to: &items)

        let id = try await client.sendText(chatId: FakeGimClient.demoDirectChatId, body: "Hi", replyTo: nil)
        await scheduler.runUntilIdle()
        var states: [SendState?] = []
        for _ in 0..<4 {
            let batch = await iterator.next()
            try DiffApplier.apply(try XCTUnwrap(batch), to: &items)
            let message = items.lazy.compactMap { item -> MessageItem? in
                if case .message(let message) = item, message.messageId == id { message } else { nil }
            }.first
            states.append(message?.sendState)
        }
        XCTAssertEqual(states, [.pending, .sent, .delivered, .read])
    }

    func testConnectionStateAndTypingStreams() async throws {
        let (client, _) = await connected(makeDemoClient())
        var connection = try await ListenerBridge.connectionState(client).makeAsyncIterator()
        let initialState = await connection.next()
        XCTAssertEqual(initialState, .connected)
        client.setNetworkReachable(reachable: false)
        let offline = await connection.next()
        XCTAssertEqual(offline, .offline)

        var typing = try await ListenerBridge.typing(client, chatId: FakeGimClient.demoGroupChatId).makeAsyncIterator()
        let nobody = await typing.next()
        XCTAssertEqual(nobody, [])
        try await client.setPeerTyping(chatId: FakeGimClient.demoGroupChatId, userId: "user-luca", active: true)
        let luca = await typing.next()
        XCTAssertEqual(luca, ["user-luca"])
    }

    func testSubscribeErrorsAreThrown() async throws {
        let (client, _) = await connected(makeDemoClient())
        do {
            _ = try await ListenerBridge.timeline(client, chatId: "missing")
            XCTFail("Expected NotFound")
        } catch {
            XCTAssertEqual(error as? GimError, .NotFound(reason: "chat missing"))
        }
    }

    func testCancellingTheConsumerEndsTheStream() async throws {
        let (client, _) = await connected(makeDemoClient())
        let stream = try await ListenerBridge.chatList(client)
        let consumer = Task {
            var batches = 0
            for await _ in stream { batches += 1 }
            return batches
        }
        consumer.cancel()
        let batches = await consumer.value
        XCTAssertLessThanOrEqual(batches, 1)
    }

    func testStreamKeepsTheSubscriptionAliveUntilItEnds() async throws {
        let (client, _) = await connected(makeDemoClient())
        var iterator = try await ListenerBridge.chatList(client).makeAsyncIterator()
        _ = await iterator.next()
        try await client.receiveText(chatId: FakeGimClient.demoGroupChatId, from: "user-luca", body: "Still here")
        let update = await iterator.next()
        XCTAssertNotNil(update)
    }
}

/// Compile-and-run check that `@Observable` works on this toolchain (ViewModels rely on it).
@MainActor @Observable
private final class ObservationProbe {
    var value = 0
}

final class ObservationAvailabilityTests: XCTestCase {
    // Synchronous `@MainActor` test methods crash Linux test discovery in swift 6.1, so hop explicitly.
    func testObservationTracksChanges() async {
        let marked = await MainActor.run {
            let probe = ObservationProbe()
            let changed = Recorder()
            withObservationTracking {
                _ = probe.value
            } onChange: {
                changed.mark()
            }
            probe.value = 1
            return changed.isMarked
        }
        XCTAssertTrue(marked)
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var marked = false
        var isMarked: Bool { lock.withLock { marked } }
        func mark() { lock.withLock { marked = true } }
    }
}
