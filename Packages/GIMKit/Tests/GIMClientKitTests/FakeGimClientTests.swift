import Foundation
import XCTest

@testable import GIMClientKit

final class FakeGimClientTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)
    private let direct = FakeGimClient.demoDirectChatId
    private let group = FakeGimClient.demoGroupChatId

    private var scheduler = ManualFakeScheduler()
    private var clock = TestClock(Date())

    override func setUp() {
        super.setUp()
        scheduler = ManualFakeScheduler()
        clock = TestClock(base)
    }

    private func makeDemo(autoReply: Bool = false) throws -> FakeGimClient {
        let clock = clock
        return FakeGimClient.demo(
            scheduler: scheduler, dataDirectory: try makeTemporaryDirectory(), now: { clock.now },
            autoReply: autoReply)
    }

    // MARK: - Account

    func testRegisterMovesFromUnregisteredToRegistered() async throws {
        let client = FakeGimClient(
            scheduler: scheduler, dataDirectory: try makeTemporaryDirectory(),
            users: [UserProfile(userId: "user-sofia", handle: "sofia", displayName: "Sofia")])
        let initialState = try await client.loginState()
        XCTAssertEqual(initialState, .unregistered)
        await assertThrows(.unauthorized) { try await client.findUser(handle: "sofia") }
        await assertThrows(.invalidInput("Display name is required")) {
            try await client.register(serverUrl: "https://gim.example", handle: "kai", displayName: " ")
        }
        await assertThrows(.invalidInput("Handle is already taken")) {
            try await client.register(serverUrl: "https://gim.example", handle: "Sofia", displayName: "Other")
        }

        let session = try await client.register(serverUrl: "https://gim.example", handle: "Kai", displayName: "Kai")
        XCTAssertEqual(session.handle, "kai")
        let state = try await client.loginState()
        XCTAssertEqual(state, .registered(session))
        let found = try await client.findUser(handle: "sofia")
        XCTAssertEqual(found?.displayName, "Sofia")
        let missing = try await client.findUser(handle: "nobody")
        XCTAssertNil(missing)
    }

    func testLogoutResetsChatList() async throws {
        let client = try makeDemo()
        let list = Recorder<[ChatListDiff]>()
        _ = try await client.subscribeChatList(list)
        try await client.logout()
        XCTAssertEqual(list.events.last, [.reset([])])
        let state = try await client.loginState()
        XCTAssertEqual(state, .unregistered)
    }

    // MARK: - Demo seed and subscriptions

    func testDemoSeed() async throws {
        let client = try makeDemo()
        for handle in ["sofia", "luca", "nikos"] {
            let user = try await client.findUser(handle: handle)
            XCTAssertNotNil(user, handle)
        }

        let list = Recorder<[ChatListDiff]>()
        _ = try await client.subscribeChatList(list)
        XCTAssertEqual(list.events.count, 1)
        XCTAssertEqual(list.items.map(\.id), [group, direct])
        XCTAssertEqual(list.items.map(\.kind), [.group, .direct])
        XCTAssertEqual(list.items.map(\.memberCount), [4, 2])
        XCTAssertEqual(list.items[1].title, "Sofia Marin")
        XCTAssertEqual(list.items[1].unreadCount, 2)

        let timeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeTimeline(direct, timeline)
        while try await client.loadOlder(direct, count: 50) {}
        let messages = timeline.items
        XCTAssertEqual(messages.count, 150)
        XCTAssertEqual(messages.map(\.timestamp), messages.map(\.timestamp).sorted())
        XCTAssertTrue(messages.contains { if case .image = $0.content { true } else { false } })
        XCTAssertTrue(messages.contains { if case .file = $0.content { true } else { false } })
        XCTAssertTrue(messages.contains { $0.content == .deleted })
        XCTAssertTrue(messages.contains { $0.replyTo != nil })
        XCTAssertTrue(messages.contains { $0.editedAt != nil })
        XCTAssertTrue(messages.contains { $0.reactions.contains { $0.includesMe } })
        XCTAssertTrue(messages.filter(\.isOwn).allSatisfy { $0.sendState != nil })
        XCTAssertTrue(messages.filter { !$0.isOwn }.allSatisfy { $0.sendState == nil })

        let details = try await client.chatDetails(group)
        XCTAssertEqual(details.members.count, 4)
        XCTAssertEqual(details.members.filter(\.isSelf).map(\.user.userId), [FakeGimClient.demoSelfId])
    }

    func testSubscriptionsDeliverCurrentStateImmediately() async throws {
        let client = try makeDemo()
        let timeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeTimeline(direct, timeline)
        guard case .reset(let window) = timeline.events.first?.first else { return XCTFail("Expected reset") }
        XCTAssertEqual(window.count, FakeGimClient.initialWindow)
        XCTAssertEqual(window.first?.id, "msg-sofia-100")
        XCTAssertEqual(window.last?.id, "msg-sofia-149")

        let connection = Recorder<ConnectionState>()
        _ = try await client.subscribeConnection(connection)
        XCTAssertEqual(connection.events, [.online])

        let typing = Recorder<[String]>()
        _ = try await client.subscribeTyping(direct, typing)
        XCTAssertEqual(typing.events, [[]])

        await assertThrows(.notFound) { try await client.subscribeTimeline("missing", timeline) }
    }

    func testCancelledSubscriptionReceivesNothing() async throws {
        let client = try makeDemo()
        let timeline = Recorder<[TimelineDiff]>()
        let handle = try await client.subscribeTimeline(direct, timeline)
        handle.cancel()
        _ = try await client.sendText(direct, text: "Hello", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(timeline.events.count, 1)
    }

    // MARK: - Sending

    func testOwnSendIsPendingThenSentDeliveredRead() async throws {
        let client = try makeDemo()
        let list = Recorder<[ChatListDiff]>()
        let timeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeChatList(list)
        _ = try await client.subscribeTimeline(direct, timeline)
        list.clear()
        timeline.clear()

        let id = try await client.sendText(direct, text: "On my way", replyTo: nil)

        XCTAssertEqual(timeline.events.count, 1)
        guard case .insert(let index, let message) = timeline.events[0].first else { return XCTFail("Expected insert") }
        XCTAssertEqual(index, 50)
        XCTAssertEqual(message.id, id)
        XCTAssertEqual(message.sendState, .pending)
        XCTAssertTrue(message.isOwn)
        XCTAssertEqual(message.timestamp, base)

        // The direct chat (index 1) moves to the top.
        XCTAssertEqual(list.events.count, 1)
        guard list.events[0].count == 2, case .remove(1) = list.events[0][0],
            case .insert(0, let summary) = list.events[0][1]
        else { return XCTFail("Expected move, got \(list.events)") }
        XCTAssertEqual(summary.id, direct)
        XCTAssertEqual(summary.lastMessagePreview, "On my way")
        XCTAssertEqual(summary.lastMessageAt, base)

        await scheduler.runUntilIdle()
        let states = timeline.events.dropFirst().map { batch -> SendState? in
            guard case .update(50, let message) = batch.first, batch.count == 1 else { return nil }
            return message.sendState
        }
        XCTAssertEqual(states, [.sent, .delivered, .read])
        XCTAssertEqual(list.events.count, 1, "status changes do not change the chat summary")
    }

    func testFailedSendCanBeRetried() async throws {
        let client = try makeDemo()
        let timeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeTimeline(direct, timeline)
        await client.failNextSends(1)

        let id = try await client.sendText(direct, text: "Fails once", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(timeline.items.last?.sendState, .failed(reason: FakeGimClient.failureReason))
        await assertThrows(.invalidInput("Message has not failed")) { try await client.retry("msg-sofia-147") }

        let failedEvents = timeline.events.count
        try await client.retry(id)
        XCTAssertEqual(timeline.items.last?.sendState, .pending)
        await scheduler.runUntilIdle()
        let states = timeline.events.dropFirst(failedEvents).joined().compactMap { diff -> SendState? in
            guard case .update(50, let message) = diff, message.id == id else { return nil }
            return message.sendState
        }
        XCTAssertEqual(states, [.pending, .sent, .delivered, .read])
    }

    func testReplyCarriesPreview() async throws {
        let client = try makeDemo()
        let timeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeTimeline(direct, timeline)
        _ = try await client.sendText(direct, text: "Agreed", replyTo: "msg-sofia-149")
        let reply = timeline.items.last?.replyTo
        XCTAssertEqual(reply?.messageId, "msg-sofia-149")
        XCTAssertEqual(reply?.senderName, "Sofia Marin")
        XCTAssertEqual(reply?.preview, textOf(timeline.items[49]))
        await assertThrows(.notFound) { try await client.sendText(direct, text: "x", replyTo: "missing") }
        await assertThrows(.invalidInput("Reply target is in another chat")) {
            try await client.sendText(self.group, text: "x", replyTo: "msg-sofia-149")
        }
        await assertThrows(.invalidInput("Message is empty")) {
            try await client.sendText(direct, text: " ", replyTo: nil)
        }
    }

    private func textOf(_ message: TimelineMessage) -> String? {
        if case .text(let text) = message.content { text } else { nil }
    }

    func testEditDeleteAndReact() async throws {
        let client = try makeDemo()
        let timeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeTimeline(direct, timeline)
        let id = try await client.sendText(direct, text: "Typo", replyTo: nil)
        clock.now = base.addingTimeInterval(60)

        timeline.clear()
        try await client.edit(id, text: "Fixed")
        XCTAssertEqual(timeline.events.count, 1)
        XCTAssertEqual(timeline.items.last?.content, .text("Fixed"))
        XCTAssertEqual(timeline.items.last?.editedAt, base.addingTimeInterval(60))

        try await client.react(id, emoji: "👍", remove: false)
        XCTAssertEqual(timeline.items.last?.reactions, [ReactionGroup(emoji: "👍", count: 1, includesMe: true)])
        try await client.react("msg-sofia-144", emoji: "👍", remove: false)
        let reacted = timeline.items.first { $0.id == "msg-sofia-144" }
        XCTAssertEqual(reacted?.reactions.first, ReactionGroup(emoji: "👍", count: 2, includesMe: true))
        try await client.react(id, emoji: "👍", remove: true)
        XCTAssertEqual(timeline.items.last?.reactions, [])

        try await client.delete(id)
        XCTAssertEqual(timeline.items.last?.content, .deleted)
        await assertThrows(.invalidInput("Only your own messages can be edited")) {
            try await client.edit("msg-sofia-149", text: "Nope")
        }
        await assertThrows(.invalidInput("Message was deleted")) {
            try await client.react(id, emoji: "👍", remove: false)
        }

        let list = Recorder<[ChatListDiff]>()
        _ = try await client.subscribeChatList(list)
        XCTAssertEqual(list.items.first?.lastMessagePreview, "Message deleted")
    }

    func testSendMediaCopiesFileAndFetchMediaReturnsIt() async throws {
        let client = try makeDemo()
        let source = URL(fileURLWithPath: try makeTemporaryDirectory()).appendingPathComponent("route.gpx")
        try Data("<gpx/>".utf8).write(to: source)
        let timeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeTimeline(direct, timeline)

        _ = try await client.sendMedia(
            direct, filePath: source.path, mime: "application/gpx+xml", kind: .file, caption: "Route", replyTo: nil,
            width: nil, height: nil)
        guard case .file(let info, let caption) = timeline.items.last?.content else { return XCTFail("Expected file") }
        XCTAssertEqual(caption, "Route")
        XCTAssertEqual(info.fileName, "route.gpx")
        XCTAssertEqual(info.size, 6)
        let path = try await client.fetchMedia(info.mediaId)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data("<gpx/>".utf8))

        let imagePath = try await client.fetchMedia("media-harbour")
        let png = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        await assertThrows(.notFound) { try await client.fetchMedia("missing") }
        await assertThrows(.invalidInput("File not found")) {
            try await client.sendMedia(
                self.direct, filePath: "/nonexistent", mime: "image/png", kind: .image, caption: nil, replyTo: nil,
                width: nil, height: nil)
        }
    }

    // MARK: - Pagination

    func testLoadOlderInsertsPagesAtTheFront() async throws {
        let client = try makeDemo()
        let timeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeTimeline(direct, timeline)
        timeline.clear()

        let hasMore = try await client.loadOlder(direct, count: 50)
        XCTAssertTrue(hasMore)
        XCTAssertEqual(timeline.events.count, 1)
        let page = timeline.events[0]
        XCTAssertEqual(page.count, 50)
        guard case .insert(0, let first) = page.first, case .insert(49, let last) = page.last else {
            return XCTFail("Expected inserts at the front")
        }
        XCTAssertEqual(first.id, "msg-sofia-050")
        XCTAssertEqual(last.id, "msg-sofia-099")

        let hasMoreAfterSecond = try await client.loadOlder(direct, count: 50)
        XCTAssertFalse(hasMoreAfterSecond)
        timeline.clear()
        let hasMoreAtStart = try await client.loadOlder(direct, count: 50)
        XCTAssertFalse(hasMoreAtStart)
        XCTAssertTrue(timeline.events.isEmpty)

        let fresh = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeTimeline(direct, fresh)
        XCTAssertEqual(fresh.items.count, 150)
        XCTAssertEqual(fresh.items.first?.id, "msg-sofia-000")
    }

    // MARK: - Chat list

    func testCreateChatInsertsAtSortedIndex() async throws {
        let client = try makeDemo()
        let list = Recorder<[ChatListDiff]>()
        _ = try await client.subscribeChatList(list)
        list.clear()

        let nikosChat = try await client.createDirectChat(with: "user-nikos")
        guard case .insert(0, let summary) = list.events.last?.first else { return XCTFail("Expected insert at 0") }
        XCTAssertEqual(summary.id, nikosChat)
        XCTAssertEqual(summary.title, "Nikos Papadopoulos")
        XCTAssertNil(summary.lastMessageAt)

        clock.now = base.addingTimeInterval(-2 * 3600)
        let older = try await client.createGroupChat(name: "Regatta", members: ["user-luca", "user-luca"])
        XCTAssertEqual(list.events.last, [.insert(index: 3, list.items[3])])
        XCTAssertEqual(list.items.map(\.id), [nikosChat, group, direct, older])
        XCTAssertEqual(list.items[3].memberCount, 2)

        list.clear()
        let existing = try await client.createDirectChat(with: "user-sofia")
        XCTAssertEqual(existing, direct)
        XCTAssertTrue(list.events.isEmpty)
        await assertThrows(.notFound) { try await client.createDirectChat(with: "user-missing") }
        await assertThrows(.notFound) { try await client.createGroupChat(name: "X", members: ["user-missing"]) }
        await assertThrows(.invalidInput("Group name is required")) {
            try await client.createGroupChat(name: " ", members: [])
        }
    }

    func testMembershipChangesUpdateChatList() async throws {
        let client = try makeDemo()
        let list = Recorder<[ChatListDiff]>()
        _ = try await client.subscribeChatList(list)
        let chat = try await client.createGroupChat(name: "Delivery crew", members: ["user-luca"])
        list.clear()

        try await client.addMember(chat, user: "user-nikos")
        XCTAssertEqual(list.events.count, 1)
        XCTAssertEqual(list.items.first { $0.id == chat }?.memberCount, 3)
        try await client.removeMember(chat, user: "user-luca")
        XCTAssertEqual(list.items.first { $0.id == chat }?.memberCount, 2)
        let details = try await client.chatDetails(chat)
        XCTAssertEqual(details.members.map(\.user.handle), ["alex", "nikos"])
        await assertThrows(.invalidInput("Members can only be added to groups")) {
            try await client.addMember(self.direct, user: "user-luca")
        }
    }

    func testMarkReadResetsUnreadWithUpdateDiff() async throws {
        let client = try makeDemo()
        let list = Recorder<[ChatListDiff]>()
        _ = try await client.subscribeChatList(list)
        list.clear()

        try await client.markRead(direct)
        guard case .update(1, let summary) = list.events.first?.first, list.events.count == 1 else {
            return XCTFail("Expected one update, got \(list.events)")
        }
        XCTAssertEqual(summary.id, direct)
        XCTAssertEqual(summary.unreadCount, 0)

        try await client.markRead(direct)
        XCTAssertEqual(list.events.count, 1, "already read: no diff")
    }

    func testIncomingMessageIncrementsUnreadAndMovesChat() async throws {
        let client = try makeDemo()
        let list = Recorder<[ChatListDiff]>()
        _ = try await client.subscribeChatList(list)
        try await client.receiveText(direct, from: "user-sofia", text: "Ahoy")
        XCTAssertEqual(list.items.map(\.id), [direct, group])
        XCTAssertEqual(list.items[0].unreadCount, 3)
        XCTAssertEqual(list.items[0].lastMessageSenderName, "Sofia Marin")
    }

    func testDiffsReplayToTheSameStateAsAFreshSubscription() async throws {
        let client = try makeDemo(autoReply: true)
        let list = Recorder<[ChatListDiff]>()
        let timeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeChatList(list)
        _ = try await client.subscribeTimeline(direct, timeline)

        _ = try await client.sendText(direct, text: "One", replyTo: nil)
        _ = try await client.sendText(group, text: "Two", replyTo: nil)
        _ = try await client.loadOlder(direct, count: 20)
        _ = try await client.createDirectChat(with: "user-luca")
        try await client.markRead(group)
        try await client.delete("msg-sofia-147")
        await scheduler.runUntilIdle()

        let freshList = Recorder<[ChatListDiff]>()
        let freshTimeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeChatList(freshList)
        _ = try await client.subscribeTimeline(direct, freshTimeline)
        XCTAssertEqual(list.items, freshList.items)
        XCTAssertEqual(timeline.items, freshTimeline.items)
        XCTAssertEqual(timeline.items.count, 50 + 20 + 2)
    }

    // MARK: - Typing and auto-reply

    func testPeerTypesThenRepliesInDirectChat() async throws {
        let client = try makeDemo(autoReply: true)
        let typing = Recorder<[String]>()
        let timeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeTyping(direct, typing)
        _ = try await client.subscribeTimeline(direct, timeline)
        typing.clear()

        _ = try await client.sendText(direct, text: "Ready?", replyTo: nil)
        await scheduler.advance(by: .seconds(2))
        XCTAssertEqual(typing.events, [["sofia"]])
        XCTAssertTrue(timeline.items.last?.isOwn ?? false)

        await scheduler.runUntilIdle()
        XCTAssertEqual(typing.events, [["sofia"], []])
        let reply = timeline.items.last
        XCTAssertEqual(reply?.senderId, "user-sofia")
        XCTAssertEqual(reply?.isOwn, false)
        XCTAssertNil(reply?.sendState)
        XCTAssertEqual(textOf(reply!), FakeDemoData.replies[0])
    }

    func testNoAutoReplyInGroups() async throws {
        let client = try makeDemo(autoReply: true)
        let typing = Recorder<[String]>()
        _ = try await client.subscribeTyping(group, typing)
        _ = try await client.sendText(group, text: "Hi all", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(typing.events, [[]])
    }

    func testSetPeerTypingValidatesMembership() async throws {
        let client = try makeDemo()
        let typing = Recorder<[String]>()
        _ = try await client.subscribeTyping(group, typing)
        try await client.setPeerTyping(group, user: "user-luca", typing: true)
        try await client.setPeerTyping(group, user: "user-nikos", typing: true)
        try await client.setPeerTyping(group, user: "user-luca", typing: false)
        XCTAssertEqual(typing.events, [[], ["luca"], ["luca", "nikos"], ["nikos"]])
        await assertThrows(.notFound) { try await client.setPeerTyping(self.direct, user: "user-luca", typing: true) }
        try await client.setTyping(group, typing: true)
    }

    // MARK: - Connection

    func testConnectionFollowsNetworkAvailabilityAndQueuesSends() async throws {
        let client = try makeDemo()
        let connection = Recorder<ConnectionState>()
        let timeline = Recorder<[TimelineDiff]>()
        _ = try await client.subscribeConnection(connection)
        _ = try await client.subscribeTimeline(direct, timeline)

        await client.setNetworkAvailable(false)
        XCTAssertEqual(connection.events, [.online, .offline])
        _ = try await client.sendText(direct, text: "Offline", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(timeline.items.last?.sendState, .pending)

        await client.setNetworkAvailable(true)
        XCTAssertEqual(connection.events, [.online, .offline, .connecting])
        await scheduler.runUntilIdle()
        XCTAssertEqual(connection.events, [.online, .offline, .connecting, .online])
        XCTAssertEqual(timeline.items.last?.sendState, .read)
    }
}
