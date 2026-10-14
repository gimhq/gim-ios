import Foundation
import GIMClientKit
import GIMFeatures
import Observation
import XCTest

final class ListenerBridgeTests: XCTestCase {
    private func makeClient() throws -> (FakeGimClient, ManualFakeScheduler) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let scheduler = ManualFakeScheduler()
        let client = FakeGimClient.demo(scheduler: scheduler, dataDirectory: directory.path, autoReply: false)
        return (client, scheduler)
    }

    func testChatListStreamStartsWithResetAndFollowsChanges() async throws {
        let (client, _) = try makeClient()
        let stream = try await ListenerBridge.chatList(client)
        var iterator = stream.makeAsyncIterator()

        var list: [ChatSummary] = []
        let first = await iterator.next()
        let reset = try DiffApplier.apply(try XCTUnwrap(first), to: &list)
        XCTAssertTrue(reset.isReset)
        XCTAssertEqual(list.count, 2)

        try await client.markRead(FakeGimClient.demoDirectChatId)
        let second = await iterator.next()
        let changes = try DiffApplier.apply(try XCTUnwrap(second), to: &list)
        XCTAssertEqual(changes.reloads, [1])
        XCTAssertEqual(list[1].unreadCount, 0)
    }

    func testTimelineStreamDeliversStatusProgression() async throws {
        let (client, scheduler) = try makeClient()
        let stream = try await ListenerBridge.timeline(client, chatId: FakeGimClient.demoDirectChatId)
        var iterator = stream.makeAsyncIterator()
        var messages: [TimelineMessage] = []
        let reset = await iterator.next()
        try DiffApplier.apply(try XCTUnwrap(reset), to: &messages)

        let id = try await client.sendText(FakeGimClient.demoDirectChatId, text: "Hi", replyTo: nil)
        await scheduler.runUntilIdle()
        var states: [SendState?] = []
        for _ in 0..<4 {
            let batch = await iterator.next()
            try DiffApplier.apply(try XCTUnwrap(batch), to: &messages)
            states.append(messages.last { $0.id == id }?.sendState)
        }
        XCTAssertEqual(states, [.pending, .sent, .delivered, .read])
    }

    func testConnectionAndTypingStreams() async throws {
        let (client, _) = try makeClient()
        var connection = try await ListenerBridge.connection(client).makeAsyncIterator()
        let initialState = await connection.next()
        XCTAssertEqual(initialState, .online)
        await client.setNetworkAvailable(false)
        let offline = await connection.next()
        XCTAssertEqual(offline, .offline)

        var typing = try await ListenerBridge.typing(client, chatId: FakeGimClient.demoGroupChatId).makeAsyncIterator()
        let nobody = await typing.next()
        XCTAssertEqual(nobody?.map(\.handle), [])
        try await client.setPeerTyping(FakeGimClient.demoGroupChatId, user: "user-luca", typing: true)
        let luca = await typing.next()
        XCTAssertEqual(luca?.map(\.handle), ["luca"])
    }

    func testSubscribeErrorsAreThrown() async throws {
        let (client, _) = try makeClient()
        do {
            _ = try await ListenerBridge.timeline(client, chatId: "missing")
            XCTFail("Expected notFound")
        } catch {
            XCTAssertEqual(error as? GimError, .notFound)
        }
    }

    func testCancellingTheConsumerEndsTheStream() async throws {
        let (client, _) = try makeClient()
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
