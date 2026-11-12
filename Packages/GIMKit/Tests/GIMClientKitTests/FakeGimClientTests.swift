import Foundation
import XCTest

@testable import GIMClientKit

final class FakeGimClientTests: XCTestCase {
    /// 2026-09-21 16:33:20 in Athens.
    private let base = Date(timeIntervalSince1970: 1_790_000_000)
    private let direct = FakeGimClient.demoDirectChatId
    private let group = FakeGimClient.demoGroupChatId

    private var scheduler = ManualFakeScheduler()
    private var clock = TestClock(Date())
    /// Subscriptions stay alive until the test ends.
    private var handles: [TaskHandle] = []
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Athens")!
        return calendar
    }

    override func setUp() {
        super.setUp()
        scheduler = ManualFakeScheduler()
        clock = TestClock(base)
        handles = []
    }

    private func keep(_ handle: TaskHandle) {
        handles.append(handle)
    }

    /// The registered demo client, connected unless `synced` is false.
    private func makeDemo(autoReply: Bool = false, synced: Bool = true) async throws -> FakeGimClient {
        let clock = clock
        let client = FakeGimClient.demo(
            scheduler: scheduler, dataDirectory: try makeTemporaryDirectory(), now: { clock.now }, autoReply: autoReply)
        await client.simulateLocalTimeZone(TimeZoneStub(calendar.timeZone))
        if synced {
            try await client.startSync()
            await scheduler.runUntilIdle()
        }
        return client
    }

    private func subscribeTimeline(
        _ client: FakeGimClient, _ chatId: String
    ) async throws -> (any Timeline, Recorder<[TimelineDiff]>) {
        let timeline = try await client.timeline(chatId: chatId)
        let recorder = Recorder<[TimelineDiff]>()
        keep(await timeline.addListener(listener: recorder))
        return (timeline, recorder)
    }

    private func subscribeChatList(_ client: FakeGimClient) async throws -> Recorder<[ChatListDiff]> {
        let recorder = Recorder<[ChatListDiff]>()
        keep(try await client.chatList(listener: recorder))
        return recorder
    }

    private func dayStartMs(_ ms: UInt64) -> UInt64 {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        return UInt64(calendar.startOfDay(for: date).timeIntervalSince1970 * 1000)
    }

    private func ms(_ date: Date) -> UInt64 {
        UInt64(date.timeIntervalSince1970 * 1000)
    }

    /// Every item is a message or membership change preceded by exactly one separator per local day.
    private func assertSeparatorsMatchDays(_ items: [TimelineItem], file: StaticString = #filePath, line: UInt = #line)
    {
        var expected: [TimelineItem] = []
        var currentDay: UInt64?
        for item in items {
            let atMs: UInt64
            switch item {
            case .dateSeparator: continue
            case .message(let message): atMs = message.sentAtMs
            case .membershipChange(_, _, let at, _, _): atMs = at
            }
            let day = dayStartMs(atMs)
            if day != currentDay {
                expected.append(.dateSeparator(dayStartMs: day))
                currentDay = day
            }
            expected.append(item)
        }
        XCTAssertEqual(items, expected, file: file, line: line)
    }

    // MARK: - Account

    func testCreateIdentityMovesFromNoSessionToSession() async throws {
        let client = FakeGimClient(
            scheduler: scheduler, dataDirectory: try makeTemporaryDirectory(),
            users: [UserProfile(userId: "user-sofia", displayName: "Sofia")])
        let initial = try await client.session()
        XCTAssertNil(initial)
        XCTAssertNil(client.userId())
        XCTAssertFalse(client.localStateReset())
        await assertThrows(.NotRegistered) { try await client.startSync() }
        XCTAssertThrowsError(try client.recoveryCode())
        await assertThrows(.InvalidInput(reason: "Display name is required")) {
            try await client.createIdentity(displayName: " ")
        }

        _ = try await client.createIdentity(displayName: " Kai ")
        let createdValue = try await client.session()
        let created = try XCTUnwrap(createdValue)
        XCTAssertEqual(created, Session(userId: created.userId, deviceId: "device-1", displayName: "Kai"))
        XCTAssertEqual(client.userId(), created.userId)
        await assertThrows(.InvalidInput(reason: "This device already has an identity")) {
            try await client.createIdentity(displayName: "Kai")
        }
    }

    func testUnregisteredDemoSeedsChatsAroundTheNewUser() async throws {
        let client = FakeGimClient.demo(
            scheduler: scheduler, dataDirectory: try makeTemporaryDirectory(), registered: false)
        let list = try await subscribeChatList(client)
        XCTAssertEqual(list.items, [])

        _ = try await client.createIdentity(displayName: "Kai Weber")
        let sessionValue = try await client.session()
        let session = try XCTUnwrap(sessionValue)

        XCTAssertEqual(list.items.map(\.chatId), [group, direct])
        let members = try await client.chatMembers(chatId: group)
        XCTAssertEqual(members.map(\.userId), [session.userId, "user-sofia", "user-luca", "user-nikos"])
        let (_, timeline) = try await subscribeTimeline(client, group)
        XCTAssertEqual(timeline.messages.filter(\.isOwn).map(\.sender.displayName), ["Kai Weber"])
    }

    func testSignOutClearsListsAndStopsSync() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        let (_, timeline) = try await subscribeTimeline(client, direct)
        let connection = Recorder<ConnectionState>()
        keep(try await client.connectionState(listener: connection))

        try await client.signOut()

        XCTAssertEqual(list.events.last, [.clear])
        XCTAssertEqual(timeline.events.last, [.clear])
        XCTAssertEqual(connection.events, [.connected, .offline])
        let session = try await client.session()
        XCTAssertNil(session)
        await assertThrows(.NotRegistered) { try await client.sendText(chatId: self.direct, body: "x", replyTo: nil) }
    }

    func testCreateClientValidatesTheServerUrl() async throws {
        let hooks = MemoryHooks(dataDir: try makeTemporaryDirectory())
        await assertThrows(.InvalidInput(reason: "server_url: unsupported scheme 'ftp'")) {
            try await createClient(config: ClientConfig(serverUrl: "ftp://gim.example.eu"), hooks: hooks)
        }
        await assertThrows(.InvalidInput(reason: "server_url: missing host")) {
            try await createClient(config: ClientConfig(serverUrl: "https://"), hooks: hooks)
        }
        let client = try await CoreGimClientFactory().make(
            config: ClientConfig(serverUrl: "https://gim.example.eu"), hooks: hooks)
        let session = try await client.session()
        XCTAssertNil(session)
    }

    // MARK: - Note to self

    func testCreateDirectChatWithYourselfCreatesTheNoteToSelfOnce() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        let me = try XCTUnwrap(client.userId())

        let note = try await client.createDirectChat(userId: me)
        let again = try await client.createDirectChat(userId: me)

        XCTAssertEqual(again, note)
        let summary = try XCTUnwrap(list.items.first { $0.chatId == note })
        XCTAssertTrue(summary.isNoteToSelf)
        XCTAssertEqual(summary.kind, .direct)
        XCTAssertEqual(summary.peer?.userId, me)
        XCTAssertEqual(summary.memberCount, 1)
        XCTAssertFalse(summary.blocked)
        XCTAssertFalse(try XCTUnwrap(list.items.first { $0.chatId == direct }).isNoteToSelf)
        let sofia = try await client.createDirectChat(userId: "user-sofia")
        XCTAssertEqual(sofia, direct, "the chat with Sofia is not the note to self")
        await assertThrows(.InvalidInput(reason: "Members can only be added to groups")) {
            try await client.addMembers(chatId: note, userIds: ["user-luca"])
        }
        _ = try await client.sendText(chatId: note, body: "Buy milk", replyTo: nil)
    }

    // MARK: - Demo seed and listeners

    func testDemoSeed() async throws {
        let client = try await makeDemo()

        let list = try await subscribeChatList(client)
        XCTAssertEqual(list.events.count, 1)
        XCTAssertEqual(list.items.map(\.chatId), [group, direct])
        XCTAssertEqual(list.items.map(\.kind), [.group, .direct])
        XCTAssertEqual(list.items.map(\.memberCount), [4, 2])
        XCTAssertEqual(list.items[1].name, "Sofia Marin")
        XCTAssertEqual(list.items[1].unreadCount, 2)
        XCTAssertEqual(list.items[0].lastMessage?.senderName, "Nikos Papadopoulos")
        XCTAssertEqual(list.items[0].updatedAtMs, list.items[0].lastMessage?.sentAtMs)

        let (timeline, recorder) = try await subscribeTimeline(client, direct)
        XCTAssertEqual(timeline.chatId(), direct)
        while try await timeline.paginateBackwards(count: 50) {}
        let messages = recorder.messages
        XCTAssertEqual(messages.count, 150)
        XCTAssertEqual(messages.map(\.sentAtMs), messages.map(\.sentAtMs).sorted())
        XCTAssertTrue(messages.contains { if case .image = $0.content { true } else { false } })
        XCTAssertTrue(messages.contains { if case .file = $0.content { true } else { false } })
        XCTAssertTrue(messages.contains { $0.content == .deleted })
        XCTAssertTrue(messages.contains { $0.replyTo != nil })
        XCTAssertTrue(messages.contains(where: \.edited))
        XCTAssertTrue(messages.contains { $0.reactions.contains(where: \.own) })
        XCTAssertTrue(messages.filter(\.isOwn).allSatisfy { $0.sendState != nil })
        XCTAssertTrue(messages.filter { !$0.isOwn }.allSatisfy { $0.sendState == nil })

        let members = try await client.chatMembers(chatId: group)
        XCTAssertEqual(
            members.map(\.displayName), ["Alex Morgan", "Sofia Marin", "Luca Bianchi", "Nikos Papadopoulos"])
    }

    func testTimelineHasADateSeparatorAtTheStartOfEachLocalDay() async throws {
        let client = try await makeDemo()
        let (timeline, recorder) = try await subscribeTimeline(client, direct)
        while try await timeline.paginateBackwards(count: 40) {}

        let items = recorder.items
        guard case .dateSeparator = items.first else { return XCTFail("Expected a separator first") }
        let separators = items.filter { if case .dateSeparator = $0 { true } else { false } }
        // 150 messages 41 minutes apart span five local days.
        XCTAssertEqual(separators.count, 5)
        assertSeparatorsMatchDays(items)

        // Without a zone the days are UTC days.
        let base = base
        let utcClient = FakeGimClient.demo(
            scheduler: scheduler, dataDirectory: try makeTemporaryDirectory(), now: { base })
        let (_, utcRecorder) = try await subscribeTimeline(utcClient, direct)
        let utcSeparators = utcRecorder.items.compactMap { if case .dateSeparator(let day) = $0 { day } else { nil } }
        XCTAssertTrue(utcSeparators.allSatisfy { $0 % 86_400_000 == 0 })
    }

    func testDaysFollowTheLocalTimeZoneAndMoveWhenItChanges() async throws {
        let hour: UInt64 = 3_600_000
        let midnight: UInt64 = 1_789_948_800_000  // 2026-09-21 00:00 UTC
        let clock = clock
        let client = FakeGimClient(
            scheduler: scheduler, dataDirectory: try makeTemporaryDirectory(), now: { clock.now },
            session: Session(userId: "user-kai", deviceId: "device-1", displayName: "Kai"))
        let chat = try await client.createGroupChat(name: "Watch", memberUserIds: [])
        let (_, timeline) = try await subscribeTimeline(client, chat)
        // 22:30 UTC on the 20th and 01:30 UTC on the 21st.
        clock.now = Date(timeIntervalSince1970: TimeInterval(midnight - 90 * 60_000) / 1000)
        _ = try await client.sendText(chatId: chat, body: "Late", replyTo: nil)
        clock.now = Date(timeIntervalSince1970: TimeInterval(midnight + 90 * 60_000) / 1000)
        _ = try await client.sendText(chatId: chat, body: "Early", replyTo: nil)
        let separators = { @Sendable in
            timeline.items.compactMap { if case .dateSeparator(let day) = $0 { day } else { nil } }
        }
        XCTAssertEqual(separators(), [midnight - 24 * hour, midnight], "UTC days by default")

        // At +02:00 both messages are on the 21st, which starts at 22:00 UTC on the 20th.
        await client.simulateLocalTimeZone(TimeZoneStub(TimeZone(secondsFromGMT: 7_200)!))
        XCTAssertEqual(separators(), [midnight - 2 * hour])
        XCTAssertEqual(timeline.items.count, 3)

        client.setLocalTimeZone(zone: nil)
        await eventually { separators() == [midnight - 24 * hour, midnight] }
    }

    func testSendOnANewDayAppendsASeparatorFirst() async throws {
        let client = try await makeDemo()
        let (_, timeline) = try await subscribeTimeline(client, direct)
        timeline.clear()

        let sameDay = try await client.sendText(chatId: direct, body: "Same day", replyTo: nil)
        guard case .pushBack(.message(let first)) = timeline.events.first?.first, timeline.events[0].count == 1 else {
            return XCTFail("Expected pushBack, got \(timeline.events)")
        }
        XCTAssertEqual(first.messageId, sameDay)

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: base)!
        clock.now = tomorrow
        timeline.clear()
        let nextDay = try await client.sendText(chatId: direct, body: "Next day", replyTo: nil)
        guard case .append(let values) = timeline.events.first?.first, values.count == 2,
            case .message(let second) = values[1]
        else { return XCTFail("Expected append, got \(timeline.events)") }
        XCTAssertEqual(values[0], .dateSeparator(dayStartMs: ms(calendar.startOfDay(for: tomorrow))))
        XCTAssertEqual(second.messageId, nextDay)
        assertSeparatorsMatchDays(timeline.items)
    }

    func testListenersDeliverCurrentStateImmediately() async throws {
        let client = try await makeDemo(synced: false)
        let (_, timeline) = try await subscribeTimeline(client, direct)
        guard case .reset(let window) = timeline.events.first?.first else { return XCTFail("Expected reset") }
        let messages = window.compactMap { if case .message(let item) = $0 { item } else { nil } }
        XCTAssertEqual(messages.count, FakeGimClient.initialWindow)
        XCTAssertEqual(messages.first?.messageId, "msg-sofia-100")
        XCTAssertEqual(messages.last?.messageId, "msg-sofia-149")
        guard case .dateSeparator = window.first else { return XCTFail("Expected a separator first") }

        let connection = Recorder<ConnectionState>()
        keep(try await client.connectionState(listener: connection))
        XCTAssertEqual(connection.events, [.offline])

        let typing = Recorder<[String]>()
        keep(try await client.typing(chatId: direct, listener: typing))
        XCTAssertEqual(typing.events, [[]])

        await assertThrows(.NotFound(reason: "chat missing")) { try await client.timeline(chatId: "missing") }
    }

    func testCancelledOrReleasedHandlesReceiveNothing() async throws {
        let client = try await makeDemo()
        let cancelled = Recorder<[TimelineDiff]>()
        let handle = try await client.timeline(chatId: direct).addListener(listener: cancelled)
        XCTAssertFalse(handle.isFinished())
        handle.cancel()
        handle.cancel()
        XCTAssertTrue(handle.isFinished())

        let released = Recorder<[ChatListDiff]>()
        _ = try await client.chatList(listener: released)
        let kept = try await subscribeChatList(client)

        _ = try await client.sendText(chatId: direct, body: "Hello", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(cancelled.events.count, 1)
        XCTAssertEqual(released.events.count, 1)
        // The reset, the send, then the sent, delivered and read ticks of the preview.
        XCTAssertEqual(kept.events.count, 5)
    }

    // MARK: - Sync and connection

    func testStartSyncConnectsThroughSyncingAndStopSyncGoesOffline() async throws {
        let client = try await makeDemo(synced: false)
        let connection = Recorder<ConnectionState>()
        keep(try await client.connectionState(listener: connection))

        try await client.startSync()
        XCTAssertEqual(connection.events, [.offline, .connecting])
        await scheduler.advance(by: .milliseconds(500))
        XCTAssertEqual(connection.events, [.offline, .connecting, .syncing])
        await scheduler.runUntilIdle()
        XCTAssertEqual(connection.events, [.offline, .connecting, .syncing, .connected])

        try await client.stopSync()
        XCTAssertEqual(connection.events.last, .offline)
    }

    func testSendsWaitInTheOutboxUntilConnected() async throws {
        let client = try await makeDemo(synced: false)
        let (_, timeline) = try await subscribeTimeline(client, direct)
        let id = try await client.sendText(chatId: direct, body: "Before sync", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(timeline.messages.last?.sendState, .pending)

        try await client.startSync()
        await scheduler.runUntilIdle()
        XCTAssertEqual(timeline.messages.last?.messageId, id)
        XCTAssertEqual(timeline.messages.last?.sendState, .read)
    }

    func testConnectionFollowsReachabilityAndQueuesSends() async throws {
        let client = try await makeDemo()
        let connection = Recorder<ConnectionState>()
        keep(try await client.connectionState(listener: connection))
        let (_, timeline) = try await subscribeTimeline(client, direct)

        await client.simulateNetworkReachable(false)
        XCTAssertEqual(connection.events, [.connected, .offline])
        _ = try await client.sendText(chatId: direct, body: "Offline", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(timeline.messages.last?.sendState, .pending)

        await client.simulateNetworkReachable(true)
        XCTAssertEqual(connection.events, [.connected, .offline, .connecting])
        await scheduler.runUntilIdle()
        XCTAssertEqual(connection.events, [.connected, .offline, .connecting, .syncing, .connected])
        XCTAssertEqual(timeline.messages.last?.sendState, .read)
    }

    func testSetNetworkReachableAppliesUpdatesInOrder() async throws {
        let client = try await makeDemo()
        let connection = Recorder<ConnectionState>()
        keep(try await client.connectionState(listener: connection))

        client.setNetworkReachable(reachable: false)
        client.setNetworkReachable(reachable: true)
        client.setNetworkReachable(reachable: false)

        await eventually { connection.events.count == 4 }
        XCTAssertEqual(connection.events, [.connected, .offline, .connecting, .offline])
        await scheduler.runUntilIdle()
        XCTAssertEqual(connection.events.last, .offline, "the stale connect step does nothing")
    }

    // MARK: - Sending

    func testOwnSendIsPendingThenSentDeliveredRead() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        let (_, timeline) = try await subscribeTimeline(client, direct)
        list.clear()
        timeline.clear()

        let id = try await client.sendText(chatId: direct, body: "On my way", replyTo: nil)

        XCTAssertEqual(timeline.events.count, 1)
        guard case .pushBack(.message(let message)) = timeline.events[0].first else {
            return XCTFail("Expected pushBack, got \(timeline.events)")
        }
        XCTAssertEqual(message.messageId, id)
        XCTAssertEqual(message.sendState, .pending)
        XCTAssertTrue(message.isOwn)
        XCTAssertEqual(message.sentAtMs, ms(base))
        XCTAssertEqual(message.sender.userId, FakeGimClient.demoSelfId)

        // The direct chat (index 1) moves to the top.
        XCTAssertEqual(list.events.count, 1)
        guard list.events[0].count == 2, case .remove(1) = list.events[0][0],
            case .pushFront(let summary) = list.events[0][1]
        else { return XCTFail("Expected move, got \(list.events)") }
        XCTAssertEqual(summary.chatId, direct)
        XCTAssertEqual(
            summary.lastMessage,
            MessagePreview(
                senderName: "Alex Morgan", text: "On my way", sentAtMs: ms(base), isOwn: true, sendState: .pending))
        XCTAssertEqual(summary.updatedAtMs, ms(base))

        await scheduler.runUntilIdle()
        let lastIndex = UInt32(timeline.items.count - 1)
        let states = timeline.events.dropFirst().map { batch -> SendState? in
            guard batch.count == 1, case .set(lastIndex, .message(let message)) = batch[0] else { return nil }
            return message.sendState
        }
        XCTAssertEqual(states, [.sent, .delivered, .read])
        // Each send state change updates the row's preview in place.
        let previewStates = list.events.dropFirst().map { batch -> SendState? in
            guard batch.count == 1, case .set(0, let summary) = batch[0], summary.chatId == direct else { return nil }
            return summary.lastMessage?.sendState
        }
        XCTAssertEqual(previewStates, [.sent, .delivered, .read])
        XCTAssertEqual(list.items[0].lastMessage?.sendState, .read)
    }

    func testFailedOwnLastMessageShowsTheFailureInThePreview() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        await client.failNextSends(1)

        _ = try await client.sendText(chatId: direct, body: "Fails", replyTo: nil)
        XCTAssertEqual(list.items[0].lastMessage?.sendState, .pending)
        list.clear()
        await scheduler.runUntilIdle()
        XCTAssertEqual(list.events, [[.set(index: 0, value: list.items[0])]])
        XCTAssertEqual(
            list.items[0].lastMessage?.sendState, .failed(reason: FakeGimClient.failureReason, cause: .other))
    }

    func testPeerLastMessagePreviewHasNoSendState() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        try await client.receiveText(chatId: direct, from: "user-sofia", body: "Ahoy")
        XCTAssertEqual(list.items[0].chatId, direct)
        XCTAssertEqual(list.items[0].lastMessage?.isOwn, false)
        XCTAssertNil(list.items[0].lastMessage?.sendState)
    }

    func testFailedSendCanBeRetriedOrCancelled() async throws {
        let client = try await makeDemo()
        let (_, timeline) = try await subscribeTimeline(client, direct)
        let list = try await subscribeChatList(client)
        await client.failNextSends(2)

        let id = try await client.sendText(chatId: direct, body: "Fails once", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(timeline.messages.last?.sendState, .failed(reason: FakeGimClient.failureReason, cause: .other))
        await assertThrows(.InvalidInput(reason: "Message has not failed")) {
            try await client.retrySend(chatId: self.direct, messageId: "msg-sofia-147")
        }

        let failedEvents = timeline.events.count
        try await client.retrySend(chatId: direct, messageId: id)
        XCTAssertEqual(timeline.messages.last?.sendState, .pending)
        await scheduler.runUntilIdle()
        let states = timeline.events.dropFirst(failedEvents).joined().compactMap { diff -> SendState? in
            guard case .set(_, .message(let message)) = diff, message.messageId == id else { return nil }
            return message.sendState
        }
        XCTAssertEqual(states, [.pending, .failed(reason: FakeGimClient.failureReason, cause: .other)])

        let itemsBefore = timeline.items.count
        timeline.clear()
        try await client.cancelSend(chatId: direct, messageId: id)
        XCTAssertEqual(timeline.events, [[.popBack]])
        XCTAssertEqual(timeline.items.count, itemsBefore - 1)
        XCTAssertFalse(timeline.messages.contains { $0.messageId == id })
        XCTAssertEqual(list.items.first { $0.chatId == direct }?.lastMessage?.text, "Hydra or Poros for tonight?")
        await assertThrows(.InvalidInput(reason: "Message was already sent")) {
            try await client.cancelSend(chatId: self.direct, messageId: "msg-sofia-147")
        }
        await assertThrows(.NotFound(reason: "message \(id)")) {
            try await client.retrySend(chatId: self.direct, messageId: id)
        }
    }

    func testReplyCarriesPreview() async throws {
        let client = try await makeDemo()
        let (_, timeline) = try await subscribeTimeline(client, direct)
        _ = try await client.sendText(chatId: direct, body: "Agreed", replyTo: "msg-sofia-149")
        let reply = timeline.messages.last?.replyTo
        let target = timeline.messages.first { $0.messageId == "msg-sofia-149" }
        XCTAssertEqual(reply?.messageId, "msg-sofia-149")
        XCTAssertEqual(reply?.senderName, "Sofia Marin")
        XCTAssertEqual(reply.map { .text(body: $0.text) }, target?.content)
        await assertThrows(.NotFound(reason: "message missing")) {
            try await client.sendText(chatId: self.direct, body: "x", replyTo: "missing")
        }
        await assertThrows(.InvalidInput(reason: "Reply target is in another chat")) {
            try await client.sendText(chatId: self.group, body: "x", replyTo: "msg-sofia-149")
        }
        await assertThrows(.InvalidInput(reason: "Message is empty")) {
            try await client.sendText(chatId: self.direct, body: " ", replyTo: nil)
        }
    }

    func testEditDeleteAndReact() async throws {
        let client = try await makeDemo()
        let (_, timeline) = try await subscribeTimeline(client, direct)
        let id = try await client.sendText(chatId: direct, body: "Typo", replyTo: nil)

        timeline.clear()
        try await client.editMessage(chatId: direct, messageId: id, newBody: "Fixed")
        XCTAssertEqual(timeline.events.count, 1)
        XCTAssertEqual(timeline.messages.last?.content, .text(body: "Fixed"))
        XCTAssertEqual(timeline.messages.last?.edited, true)

        try await client.react(chatId: direct, messageId: id, emoji: "👍")
        XCTAssertEqual(timeline.messages.last?.reactions, [ReactionGroup(emoji: "👍", count: 1, own: true)])
        try await client.react(chatId: direct, messageId: "msg-sofia-144", emoji: "👍")
        let reacted = timeline.messages.first { $0.messageId == "msg-sofia-144" }
        XCTAssertEqual(reacted?.reactions.first, ReactionGroup(emoji: "👍", count: 2, own: true))
        try await client.unreact(chatId: direct, messageId: id, emoji: "👍")
        XCTAssertEqual(timeline.messages.last?.reactions, [])

        try await client.deleteMessage(chatId: direct, messageId: id)
        XCTAssertEqual(timeline.messages.last?.content, .deleted)
        XCTAssertEqual(timeline.messages.last?.edited, false)
        await assertThrows(.InvalidInput(reason: "Only your own messages can be edited")) {
            try await client.editMessage(chatId: self.direct, messageId: "msg-sofia-149", newBody: "Nope")
        }
        await assertThrows(.InvalidInput(reason: "Message was deleted")) {
            try await client.react(chatId: self.direct, messageId: id, emoji: "👍")
        }
        await assertThrows(.NotFound(reason: "message \(id)")) {
            try await client.editMessage(chatId: self.group, messageId: id, newBody: "Wrong chat")
        }

        let list = try await subscribeChatList(client)
        XCTAssertEqual(list.items.first?.lastMessage?.text, "Message deleted")
    }

    func testSendMediaCopiesFileAndFetchWritesToDestPath() async throws {
        let client = try await makeDemo()
        let directory = URL(fileURLWithPath: try makeTemporaryDirectory())
        let source = directory.appendingPathComponent("route.gpx")
        try Data("<gpx/>".utf8).write(to: source)
        let (_, timeline) = try await subscribeTimeline(client, direct)

        let fileId = try await client.sendMedia(
            chatId: direct, filePath: source.path, mime: "application/gpx+xml", caption: "Route", replyTo: nil)
        guard case .file(let media, let fileName, let caption) = timeline.messages.last?.content else {
            return XCTFail("Expected file")
        }
        XCTAssertEqual(caption, "Route")
        XCTAssertEqual(fileName, "route.gpx")
        XCTAssertEqual(
            media,
            MediaRef(chatId: direct, messageId: fileId, mime: "application/gpx+xml", size: 6, hasThumbnail: false))
        try FileManager.default.removeItem(at: source)
        let dest = directory.appendingPathComponent("out/route.gpx").path
        let path = try await client.fetchMedia(chatId: direct, messageId: fileId, destPath: dest)
        XCTAssertEqual(path, dest)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data("<gpx/>".utf8))
        let noThumbnail = try await client.fetchThumbnail(
            chatId: direct, messageId: fileId, destPath: directory.appendingPathComponent("thumb").path)
        XCTAssertNil(noThumbnail)

        let demoImage = directory.appendingPathComponent("harbour.png").path
        let imagePath = try await client.fetchMedia(chatId: direct, messageId: "msg-sofia-060", destPath: demoImage)
        let png = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let thumbnail = try await client.fetchThumbnail(
            chatId: direct, messageId: "msg-sofia-140", destPath: directory.appendingPathComponent("t.png").path)
        XCTAssertEqual(try thumbnail.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }, png)

        let imageId = try await client.sendMedia(
            chatId: direct, filePath: demoImage, mime: "image/png", caption: nil, replyTo: nil)
        guard case .image(let imageRef, _, _, nil) = timeline.messages.last?.content else {
            return XCTFail("Expected image")
        }
        XCTAssertEqual(imageRef.messageId, imageId)
        XCTAssertTrue(imageRef.hasThumbnail)

        await assertThrows(.NotFound(reason: "media msg-sofia-149")) {
            try await client.fetchMedia(chatId: self.direct, messageId: "msg-sofia-149", destPath: dest)
        }
        await assertThrows(.InvalidInput(reason: "File not found")) {
            try await client.sendMedia(
                chatId: self.direct, filePath: "/nonexistent", mime: "image/png", caption: nil, replyTo: nil)
        }
    }

    // MARK: - Pagination

    func testPaginateBackwardsInsertsOlderItemsAtTheFront() async throws {
        let client = try await makeDemo()
        let (timeline, recorder) = try await subscribeTimeline(client, direct)
        let window = recorder.items
        recorder.clear()

        let hasMore = try await timeline.paginateBackwards(count: 50)
        XCTAssertTrue(hasMore)
        XCTAssertEqual(recorder.events.count, 1)
        for diff in recorder.events[0] {
            switch diff {
            case .set, .insert, .pushFront: break
            default: XCTFail("Unexpected \(diff)")
            }
        }
        XCTAssertEqual(recorder.messages.count, 100)
        XCTAssertEqual(recorder.messages.first?.messageId, "msg-sofia-050")
        XCTAssertEqual(Array(recorder.items.suffix(window.count - 1)), Array(window.dropFirst()))
        assertSeparatorsMatchDays(recorder.items)

        let hasMoreAfterSecond = try await timeline.paginateBackwards(count: 50)
        XCTAssertFalse(hasMoreAfterSecond)
        recorder.clear()
        let hasMoreAtStart = try await timeline.paginateBackwards(count: 50)
        XCTAssertFalse(hasMoreAtStart)
        XCTAssertTrue(recorder.events.isEmpty)

        let (_, fresh) = try await subscribeTimeline(client, direct)
        XCTAssertEqual(fresh.messages.count, 150)
        XCTAssertEqual(fresh.messages.first?.messageId, "msg-sofia-000")
        XCTAssertEqual(fresh.items, recorder.items)
    }

    // MARK: - Chat list and membership

    func testCreateChatInsertsAtSortedPosition() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        list.clear()

        let nikosChat = try await client.createDirectChat(userId: "user-nikos")
        guard case .pushFront(let summary) = list.events.last?.first else { return XCTFail("Expected pushFront") }
        XCTAssertEqual(summary.chatId, nikosChat)
        XCTAssertEqual(summary.name, "Nikos Papadopoulos")
        XCTAssertNil(summary.lastMessage)
        XCTAssertEqual(summary.updatedAtMs, ms(base))

        clock.now = base.addingTimeInterval(-2 * 3600)
        let older = try await client.createGroupChat(name: "Regatta", memberUserIds: ["user-luca", "user-luca"])
        XCTAssertEqual(list.events.last, [.pushBack(value: list.items[3])])
        XCTAssertEqual(list.items.map(\.chatId), [nikosChat, group, direct, older])
        XCTAssertEqual(list.items[3].memberCount, 2)

        clock.now = base.addingTimeInterval(-30 * 60)
        let middle = try await client.createGroupChat(name: "Delivery", memberUserIds: [])
        XCTAssertEqual(list.events.last, [.insert(index: 2, value: list.items[2])])
        XCTAssertEqual(list.items[2].chatId, middle)

        list.clear()
        let existing = try await client.createDirectChat(userId: "user-sofia")
        XCTAssertEqual(existing, direct)
        XCTAssertTrue(list.events.isEmpty)
        await assertThrows(.NotFound(reason: "user user-missing")) {
            try await client.createDirectChat(userId: "user-missing")
        }
        await assertThrows(.NotFound(reason: "users user-missing")) {
            try await client.createGroupChat(name: "X", memberUserIds: ["user-missing"])
        }
        await assertThrows(.InvalidInput(reason: "Group name is required")) {
            try await client.createGroupChat(name: " ", memberUserIds: [])
        }
    }

    func testMembershipChangesUpdateChatListAndTimeline() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        let chat = try await client.createGroupChat(name: "Delivery crew", memberUserIds: ["user-luca"])
        let (_, timeline) = try await subscribeTimeline(client, chat)
        XCTAssertEqual(timeline.items, [])
        list.clear()

        try await client.addMembers(chatId: chat, userIds: ["user-nikos", "user-sofia", "user-nikos", "user-luca"])
        XCTAssertEqual(list.items.first { $0.chatId == chat }?.memberCount, 4)
        let atMs = ms(base)
        let me = FakeGimClient.demoSelfId
        XCTAssertEqual(
            timeline.items,
            [
                .dateSeparator(dayStartMs: dayStartMs(atMs)),
                .membershipChange(
                    userName: "Nikos Papadopoulos", change: .added, atMs: atMs, userId: "user-nikos", actorUserId: me),
                .membershipChange(
                    userName: "Sofia Marin", change: .added, atMs: atMs, userId: "user-sofia", actorUserId: me),
            ])

        try await client.removeMember(chatId: chat, userId: "user-luca")
        XCTAssertEqual(list.items.first { $0.chatId == chat }?.memberCount, 3)
        XCTAssertEqual(
            timeline.items.last,
            .membershipChange(
                userName: "Luca Bianchi", change: .removed, atMs: atMs, userId: "user-luca", actorUserId: me))
        let members = try await client.chatMembers(chatId: chat)
        XCTAssertEqual(members.map(\.userId), ["user-alex", "user-nikos", "user-sofia"])

        await assertThrows(.InvalidInput(reason: "Members can only be added to groups")) {
            try await client.addMembers(chatId: self.direct, userIds: ["user-luca"])
        }
        await assertThrows(.InvalidInput(reason: "Use leaveChat to leave a group")) {
            try await client.removeMember(chatId: chat, userId: FakeGimClient.demoSelfId)
        }
        await assertThrows(.NotFound(reason: "member user-luca")) {
            try await client.removeMember(chatId: chat, userId: "user-luca")
        }
    }

    func testChatMembersFailureInjection() async throws {
        let client = try await makeDemo()
        await client.failChatMembers(with: .Network(reason: "offline"))
        await assertThrows(.Network(reason: "offline")) { try await client.chatMembers(chatId: self.group) }
        await client.failChatMembers(with: nil)
        let members = try await client.chatMembers(chatId: direct)
        XCTAssertEqual(members.map(\.userId), [FakeGimClient.demoSelfId, "user-sofia"])
    }

    func testUnknownAndDevicelessInviteesAreSkipped() async throws {
        let client = try await makeDemo()
        await client.addRemoteUser(UserProfile(userId: "user-kai", displayName: "Kai"), hasDevice: false)
        await assertThrows(.NotFound(reason: "user user-kai has no device")) {
            try await client.createDirectChat(userId: "user-kai")
        }
        await assertThrows(.NotFound(reason: "users user-kai, user-missing")) {
            try await client.createGroupChat(name: "X", memberUserIds: ["user-kai", "user-missing"])
        }

        let chat = try await client.createGroupChat(name: "Regatta", memberUserIds: ["user-luca", "user-missing"])
        let (_, timeline) = try await subscribeTimeline(client, chat)
        let atMs = ms(base)
        let me = FakeGimClient.demoSelfId
        XCTAssertEqual(
            timeline.items,
            [
                .dateSeparator(dayStartMs: dayStartMs(atMs)),
                .membershipChange(
                    userName: "user-missing", change: .removed, atMs: atMs, userId: "user-missing", actorUserId: me),
            ])
        var members = try await client.chatMembers(chatId: chat)
        XCTAssertEqual(members.map(\.userId), [FakeGimClient.demoSelfId, "user-luca"])

        await assertThrows(.NotFound(reason: "users user-kai")) {
            try await client.addMembers(chatId: chat, userIds: ["user-kai", "user-luca"])
        }
        try await client.addMembers(chatId: chat, userIds: ["user-nikos", "user-kai"])
        XCTAssertEqual(
            Array(timeline.items.suffix(2)),
            [
                .membershipChange(
                    userName: "Nikos Papadopoulos", change: .added, atMs: atMs, userId: "user-nikos", actorUserId: me),
                .membershipChange(userName: "Kai", change: .removed, atMs: atMs, userId: "user-kai", actorUserId: me),
            ])
        members = try await client.chatMembers(chatId: chat)
        XCTAssertEqual(members.map(\.userId), [FakeGimClient.demoSelfId, "user-luca", "user-nikos"])
    }

    func testRemoteUserAddedToTheDirectory() async throws {
        let client = try await makeDemo()
        let marta = UserProfile(userId: "user-marta", displayName: "Marta")
        await client.addRemoteUser(marta)

        try await client.addMembers(chatId: group, userIds: [marta.userId])

        let members = try await client.chatMembers(chatId: group)
        XCTAssertEqual(members.last, marta)
    }

    func testFetchMediaFailsOnceWhenInjected() async throws {
        let client = try await makeDemo()
        let destination = URL(fileURLWithPath: try makeTemporaryDirectory()).appendingPathComponent("photo").path
        let failure = GimError.RetryLater(status: 503, retryAfterSecs: 5, reason: "peer_unavailable")
        await client.failNextFetchMedia(with: failure)

        await assertThrows(failure) {
            try await client.fetchMedia(chatId: self.direct, messageId: "msg-sofia-140", destPath: destination)
        }
        let path = try await client.fetchMedia(chatId: direct, messageId: "msg-sofia-140", destPath: destination)
        XCTAssertEqual(path, destination)
    }

    func testLeaveChatIsLeavingUntilTheLeftChangeArrives() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        let (timeline, recorder) = try await subscribeTimeline(client, group)
        XCTAssertEqual(list.items.first { $0.chatId == group }?.state, .active)
        XCTAssertEqual(timeline.chatState(), .active)
        list.clear()

        try await client.leaveChat(chatId: group)

        XCTAssertEqual(list.events.count, 1)
        guard case .set(0, let leaving) = list.events.first?.first else {
            return XCTFail("Expected a set of the row, got \(list.events)")
        }
        XCTAssertEqual(leaving.state, .leaving)
        XCTAssertEqual(list.items.map(\.chatId), [group, direct])
        let leavingState = try await client.chatState(chatId: group)
        XCTAssertEqual(leavingState, .leaving)
        XCTAssertEqual(timeline.chatState(), .leaving)
        let refusal = GimError.ChatNotActive(chatId: group, state: .leaving)
        await assertThrows(refusal) { try await client.sendText(chatId: self.group, body: "Hi", replyTo: nil) }
        await assertThrows(refusal) {
            try await client.sendMedia(
                chatId: self.group, filePath: "/nonexistent", mime: "image/png", caption: nil, replyTo: nil)
        }
        // Calling it again re-sends the leave and does not restart the delay.
        await scheduler.advance(by: .seconds(1))
        try await client.leaveChat(chatId: group)

        clock.now = base.addingTimeInterval(2)
        await scheduler.advance(by: FakeGimClient.leaveCommitDelay - .seconds(1))

        let me = FakeGimClient.demoSelfId
        XCTAssertEqual(
            recorder.items.last,
            .membershipChange(
                userName: "Alex Morgan", change: .left, atMs: ms(clock.now), userId: me, actorUserId: me))
        // The chat stays with its history.
        XCTAssertEqual(list.items.map(\.chatId), [group, direct])
        XCTAssertEqual(list.items.first?.state, .left)
        XCTAssertEqual(list.items.first?.memberCount, 3)
        XCTAssertEqual(timeline.chatState(), .left)
        let leftState = try await client.chatState(chatId: group)
        XCTAssertEqual(leftState, .left)
        await assertThrows(.ChatNotActive(chatId: group, state: .left)) {
            try await client.leaveChat(chatId: self.group)
        }
        await assertThrows(.InvalidInput(reason: "Only groups can be left")) {
            try await client.leaveChat(chatId: self.direct)
        }
        await assertThrows(.NotFound(reason: "chat chat-none")) { try await client.chatState(chatId: "chat-none") }
    }

    func testEveryChangeToAChatThatIsNotActiveThrowsChatNotActive() async throws {
        let client = try await makeDemo()
        let avatar = URL(fileURLWithPath: try makeTemporaryDirectory()).appendingPathComponent("a.png")
        try Data([1]).write(to: avatar)
        let own = "msg-crew-2"
        await client.failNextSends(1)
        let failed = try await client.sendText(chatId: group, body: "Fails", replyTo: nil)
        await scheduler.runUntilIdle()
        try await client.leaveChat(chatId: group)

        for state in [ChatState.leaving, .left] {
            if state == .left {
                await scheduler.advance(by: FakeGimClient.leaveCommitDelay)
            }
            let refusal = GimError.ChatNotActive(chatId: group, state: state)
            await assertThrows(refusal) { try await client.sendText(chatId: self.group, body: "Hi", replyTo: nil) }
            await assertThrows(refusal) {
                try await client.sendMedia(
                    chatId: self.group, filePath: avatar.path, mime: "image/png", caption: nil, replyTo: nil)
            }
            await assertThrows(refusal) {
                try await client.editMessage(chatId: self.group, messageId: own, newBody: "Edited")
            }
            await assertThrows(refusal) { try await client.deleteMessage(chatId: self.group, messageId: own) }
            await assertThrows(refusal) { try await client.react(chatId: self.group, messageId: own, emoji: "👍") }
            await assertThrows(refusal) { try await client.unreact(chatId: self.group, messageId: own, emoji: "👍") }
            await assertThrows(refusal) { try await client.retrySend(chatId: self.group, messageId: failed) }
            await assertThrows(refusal) {
                try await client.setGroupInfo(chatId: self.group, name: "Crew", avatarFilePath: nil)
            }
            await assertThrows(refusal) { try await client.addMembers(chatId: self.group, userIds: ["user-nikos"]) }
            await assertThrows(refusal) { try await client.removeMember(chatId: self.group, userId: "user-nikos") }
        }
        // Reading, cancelling and marking read still work.
        try await client.cancelSend(chatId: group, messageId: failed)
        try await client.markRead(chatId: group, upToMessageId: own)
        _ = try await client.chatMembers(chatId: group)
    }

    func testRemovalByAnotherMemberLeavesTheChatAtOnce() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        let (timeline, recorder) = try await subscribeTimeline(client, group)

        try await client.simulateRemoval(chatId: group, by: "user-luca")

        let me = FakeGimClient.demoSelfId
        XCTAssertEqual(
            recorder.items.last,
            .membershipChange(
                userName: "Alex Morgan", change: .removed, atMs: ms(base), userId: me, actorUserId: "user-luca"))
        XCTAssertEqual(list.items.first { $0.chatId == group }?.state, .left)
        XCTAssertEqual(timeline.chatState(), .left)
        let members = try await client.chatMembers(chatId: group)
        XCTAssertFalse(members.contains { $0.userId == me })
        await assertThrows(.ChatNotActive(chatId: group, state: .left)) {
            try await client.sendText(chatId: self.group, body: "Hi", replyTo: nil)
        }
        await assertThrows(.ChatNotActive(chatId: group, state: .left)) {
            try await client.simulateRemoval(chatId: self.group, by: "user-luca")
        }
    }

    func testLeavingChatRemovedByAnotherMemberEndsLeft() async throws {
        let client = try await makeDemo()
        let (_, recorder) = try await subscribeTimeline(client, group)
        try await client.leaveChat(chatId: group)

        try await client.simulateRemoval(chatId: group, by: "user-nikos")
        await scheduler.advance(by: FakeGimClient.leaveCommitDelay)

        let changes = recorder.items.filter {
            if case .membershipChange = $0 { true } else { false }
        }
        XCTAssertEqual(changes.count, 1, "the scheduled commit adds no second change")
        let state = try await client.chatState(chatId: group)
        XCTAssertEqual(state, .left)
    }

    func testRejectedSendFailsAtOnceAndIsNotResent() async throws {
        let client = try await makeDemo(synced: false)
        let (_, timeline) = try await subscribeTimeline(client, direct)
        await client.rejectNextSend()

        let id = try await client.sendText(chatId: direct, body: "Rejected", replyTo: nil)

        XCTAssertEqual(timeline.messages.last?.messageId, id)
        XCTAssertEqual(
            timeline.messages.last?.sendState, .failed(reason: "rejected (403 not_member)", cause: .rejected))
        try await client.startSync()
        await scheduler.runUntilIdle()
        XCTAssertEqual(
            timeline.messages.last?.sendState, .failed(reason: "rejected (403 not_member)", cause: .rejected))

        // Only the next send is rejected; a retry goes through.
        try await client.retrySend(chatId: direct, messageId: id)
        let next = try await client.sendText(chatId: direct, body: "Accepted", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(timeline.messages.first { $0.messageId == id }?.sendState, .read)
        XCTAssertEqual(timeline.messages.first { $0.messageId == next }?.sendState, .read)
    }

    func testSetGroupInfoRenamesAndSetsTheAvatar() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        let directory = URL(fileURLWithPath: try makeTemporaryDirectory())
        let avatar = directory.appendingPathComponent("crew.png")
        try Data([1, 2, 3]).write(to: avatar)

        try await client.setGroupInfo(chatId: group, name: " Ionian Crew ", avatarFilePath: nil)
        XCTAssertEqual(list.items[0].name, "Ionian Crew")
        XCTAssertNil(list.items[0].avatar)

        try await client.setGroupInfo(chatId: group, name: nil, avatarFilePath: avatar.path)
        let ref = try XCTUnwrap(list.items[0].avatar)
        XCTAssertEqual(list.items[0].name, "Ionian Crew")
        XCTAssertEqual(ref.mime, "image/png")
        XCTAssertEqual(ref.size, 3)
        XCTAssertTrue(ref.hasThumbnail)
        let path = try await client.fetchThumbnail(
            chatId: ref.chatId, messageId: ref.messageId, destPath: directory.appendingPathComponent("a.png").path)
        XCTAssertEqual(try path.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }, Data([1, 2, 3]))

        await assertThrows(.InvalidInput(reason: "Group name is required")) {
            try await client.setGroupInfo(chatId: self.group, name: " ", avatarFilePath: nil)
        }
        await assertThrows(.InvalidInput(reason: "Set a name or an avatar")) {
            try await client.setGroupInfo(chatId: self.group, name: nil, avatarFilePath: nil)
        }
        await assertThrows(.InvalidInput(reason: "Only groups have a name and avatar")) {
            try await client.setGroupInfo(chatId: self.direct, name: "Sofia", avatarFilePath: nil)
        }
    }

    func testMarkReadUpToAMessage() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        list.clear()

        try await client.markRead(chatId: direct, upToMessageId: "msg-sofia-149")
        guard case .set(1, let summary) = list.events.first?.first, list.events.count == 1 else {
            return XCTFail("Expected one set, got \(list.events)")
        }
        XCTAssertEqual(summary.chatId, direct)
        XCTAssertEqual(summary.unreadCount, 0)
        try await client.markRead(chatId: direct, upToMessageId: "msg-sofia-149")
        XCTAssertEqual(list.events.count, 1, "already read: no diff")

        let first = try await client.receiveText(chatId: direct, from: "user-sofia", body: "One")
        try await client.receiveText(chatId: direct, from: "user-sofia", body: "Two")
        XCTAssertEqual(list.items[0].unreadCount, 2)
        try await client.markRead(chatId: direct, upToMessageId: first)
        XCTAssertEqual(list.items[0].unreadCount, 1)
        await assertThrows(.NotFound(reason: "message missing")) {
            try await client.markRead(chatId: self.direct, upToMessageId: "missing")
        }
    }

    func testIncomingMessageIncrementsUnreadAndMovesChat() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        try await client.receiveText(chatId: direct, from: "user-sofia", body: "Ahoy")
        XCTAssertEqual(list.items.map(\.chatId), [direct, group])
        XCTAssertEqual(list.items[0].unreadCount, 3)
        XCTAssertEqual(list.items[0].lastMessage?.senderName, "Sofia Marin")
        XCTAssertEqual(list.items[0].lastMessage?.isOwn, false)
    }

    func testDiffsReplayToTheSameStateAsAFreshSubscription() async throws {
        let client = try await makeDemo(autoReply: true)
        let list = try await subscribeChatList(client)
        let (timeline, recorder) = try await subscribeTimeline(client, direct)

        _ = try await client.sendText(chatId: direct, body: "One", replyTo: nil)
        _ = try await client.sendText(chatId: group, body: "Two", replyTo: nil)
        _ = try await timeline.paginateBackwards(count: 20)
        _ = try await client.createDirectChat(userId: "user-luca")
        try await client.markRead(chatId: group, upToMessageId: "msg-crew-5")
        try await client.deleteMessage(chatId: direct, messageId: "msg-sofia-147")
        try await client.addMembers(chatId: group, userIds: [])
        clock.now = calendar.date(byAdding: .day, value: 1, to: base)!
        await client.failNextSends(1)
        let failing = try await client.sendText(chatId: direct, body: "Tomorrow", replyTo: nil)
        await scheduler.runUntilIdle()
        try await client.cancelSend(chatId: direct, messageId: failing)
        try await client.setGroupInfo(chatId: group, name: "Crew", avatarFilePath: nil)
        await scheduler.runUntilIdle()

        let freshList = try await subscribeChatList(client)
        let (_, freshTimeline) = try await subscribeTimeline(client, direct)
        XCTAssertEqual(list.items, freshList.items)
        XCTAssertEqual(recorder.items, freshTimeline.items)
        XCTAssertEqual(recorder.messages.count, 50 + 20 + 2)
        assertSeparatorsMatchDays(recorder.items)
    }

    // MARK: - Typing and auto-reply

    func testPeerTypesThenRepliesInDirectChat() async throws {
        let client = try await makeDemo(autoReply: true)
        let typing = Recorder<[String]>()
        keep(try await client.typing(chatId: direct, listener: typing))
        let (_, timeline) = try await subscribeTimeline(client, direct)
        typing.clear()

        _ = try await client.sendText(chatId: direct, body: "Ready?", replyTo: nil)
        await scheduler.advance(by: .seconds(2))
        XCTAssertEqual(typing.events, [["user-sofia"]])
        XCTAssertEqual(timeline.messages.last?.isOwn, true)

        await scheduler.runUntilIdle()
        XCTAssertEqual(typing.events, [["user-sofia"], []])
        let reply = timeline.messages.last
        XCTAssertEqual(reply?.sender.userId, "user-sofia")
        XCTAssertEqual(reply?.isOwn, false)
        XCTAssertNil(reply?.sendState)
        XCTAssertEqual(reply?.content, .text(body: FakeDemoData.replies[0]))
    }

    func testNoAutoReplyInGroups() async throws {
        let client = try await makeDemo(autoReply: true)
        let typing = Recorder<[String]>()
        keep(try await client.typing(chatId: group, listener: typing))
        _ = try await client.sendText(chatId: group, body: "Hi all", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(typing.events, [[]])
    }

    func testSetPeerTypingValidatesMembership() async throws {
        let client = try await makeDemo()
        let typing = Recorder<[String]>()
        keep(try await client.typing(chatId: group, listener: typing))
        try await client.setPeerTyping(chatId: group, userId: "user-luca", active: true)
        try await client.setPeerTyping(chatId: group, userId: "user-nikos", active: true)
        try await client.setPeerTyping(chatId: group, userId: "user-luca", active: false)
        XCTAssertEqual(typing.events, [[], ["user-luca"], ["user-luca", "user-nikos"], ["user-nikos"]])
        await assertThrows(.NotFound(reason: "member user-luca")) {
            try await client.setPeerTyping(chatId: self.direct, userId: "user-luca", active: true)
        }
        try await client.setTyping(chatId: group, active: true)
    }

    func testSendsFailWithTheirTypedCause() async throws {
        let client = try await makeDemo(synced: false)
        let (_, timeline) = try await subscribeTimeline(client, direct)

        await client.simulateSuspension(hubId: "hub-a")
        _ = try await client.sendText(chatId: direct, body: "Suspended", replyTo: nil)
        XCTAssertEqual(
            timeline.messages.last?.sendState, .failed(reason: "user suspended on hub hub-a", cause: .userSuspended))
        await client.simulateSuspension(hubId: nil)

        await client.simulateNotAdmitted(hubId: "")
        _ = try await client.sendText(chatId: direct, body: "Not admitted", replyTo: nil)
        XCTAssertEqual(
            timeline.messages.last?.sendState, .failed(reason: "user not admitted on hub ", cause: .userNotAdmitted))
        await client.simulateNotAdmitted(hubId: nil)

        await client.simulateNotAdmittedByPeer(chatId: direct, hubId: "hub-b")
        _ = try await client.sendText(chatId: direct, body: "Refused by the peer", replyTo: nil)
        guard case .failed(_, .notAdmittedByPeer)? = timeline.messages.last?.sendState else {
            return XCTFail("expected notAdmittedByPeer, got \(String(describing: timeline.messages.last?.sendState))")
        }
        await client.simulateNotAdmittedByPeer(chatId: direct, hubId: nil)

        let id = try await client.sendText(chatId: direct, body: "Accepted", replyTo: nil)
        XCTAssertEqual(timeline.messages.last?.messageId, id)
        XCTAssertEqual(timeline.messages.last?.sendState, .pending)
    }

    func testPeerRefusalRefusesMemberChangesAndLeaveOfThatChatOnly() async throws {
        let client = try await makeDemo()
        await client.simulateNotAdmittedByPeer(chatId: group, hubId: "hub-b")
        let refused = GimError.NotAdmittedByPeer(hubId: "hub-b", chatId: group)

        await assertThrows(refused) { try await client.addMembers(chatId: self.group, userIds: ["user-luca"]) }
        await assertThrows(refused) { try await client.leaveChat(chatId: self.group) }
        let state = try await client.chatState(chatId: group)
        XCTAssertEqual(state, .active)
        _ = try await client.createGroupChat(name: "Other", memberUserIds: ["user-luca"])
    }

    func testRefusedContactsAreSkippedUnlessNobodyCanBeAdded() async throws {
        let client = try await makeDemo()
        await client.refuseContacts(["user-luca", "user-nikos"])

        await assertThrows(.ContactNotAdmitted(userIds: ["user-luca"])) {
            _ = try await client.createDirectChat(userId: "user-luca")
        }
        await assertThrows(.ContactNotAdmitted(userIds: ["user-luca", "user-nikos"])) {
            _ = try await client.createGroupChat(name: "Regatta", memberUserIds: ["user-luca", "user-nikos"])
        }
        await assertThrows(.ContactNotAdmitted(userIds: ["user-nikos"])) {
            _ = try await client.createGroupChat(name: "Regatta", memberUserIds: ["user-missing", "user-nikos"])
        }
        let chat = try await client.createGroupChat(name: "Regatta", memberUserIds: ["user-sofia", "user-luca"])
        var members = try await client.chatMembers(chatId: chat)
        XCTAssertEqual(members.map(\.userId), [FakeGimClient.demoSelfId, "user-sofia"])

        await assertThrows(.ContactNotAdmitted(userIds: ["user-nikos"])) {
            try await client.addMembers(chatId: chat, userIds: ["user-nikos"])
        }
        await client.addRemoteUser(UserProfile(userId: "user-kai", displayName: "Kai"))
        try await client.addMembers(chatId: chat, userIds: ["user-nikos", "user-kai"])
        members = try await client.chatMembers(chatId: chat)
        XCTAssertEqual(members.map(\.userId), [FakeGimClient.demoSelfId, "user-sofia", "user-kai"])
        let (_, timeline) = try await subscribeTimeline(client, chat)
        let removed = timeline.items.compactMap { item -> String? in
            guard case .membershipChange(_, .removed, _, let userId, _) = item else { return nil }
            return userId
        }
        XCTAssertEqual(removed, ["user-luca", "user-nikos"], "each refused invitee shows as removed")
    }
}

/// In-memory `PlatformHooks`.
final class MemoryHooks: PlatformHooks, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private let directory: String

    init(dataDir: String) {
        directory = dataDir
    }

    func secureStoreGet(key: String) throws -> Data? { lock.withLock { values[key] } }
    func secureStoreSet(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func secureStoreDelete(key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
    func dataDir() -> String { directory }
    func isNetworkReachable() -> Bool { true }
}
