import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

private let alice = UserProfile(userId: "u-alice", handle: "alice", displayName: "Alice")
private let bob = UserProfile(userId: "u-bob", handle: "bob", displayName: "Bob")
private let minute: UInt64 = 60_000
/// 2026-10-15 10:00 UTC.
private let builderNow = Date(timeIntervalSince1970: 1_792_058_400)
private let nowMs = UInt64(builderNow.timeIntervalSince1970 * 1000)

private func calendar(_ timeZone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone)!
    return calendar
}

private func makeBuilder(timeZone: String = "UTC") -> TimelineItemBuilder {
    TimelineItemBuilder(calendar: calendar(timeZone), locale: Locale(identifier: "de_DE"), now: { builderNow })
}

private func message(
    _ id: String, _ sender: UserProfile, at sentAtMs: UInt64, content: MessageContent = .text(body: "hi"),
    isOwn: Bool = false, sendState: SendState? = nil, replyTo: ReplyPreview? = nil, reactions: [ReactionGroup] = [],
    edited: Bool = false
) -> TimelineItem {
    .message(
        item: MessageItem(
            messageId: id, chatId: "chat", sender: sender, isOwn: isOwn, sentAtMs: sentAtMs, content: content,
            replyTo: replyTo, reactions: reactions, edited: edited, sendState: sendState))
}

private func rows(_ items: [TimelineDisplayItem]) -> [TimelineMessageRow] {
    items.compactMap(\.messageRow)
}

final class TimelineItemBuilderTests: XCTestCase {
    func testDateSeparatorLabelsUseCalendarTimeZone() {
        // Midnight of 2026-10-15 in Athens (UTC+3) is 2026-10-14 21:00 UTC.
        let athensMidnight = nowMs - 13 * 60 * minute
        let athens = makeBuilder(timeZone: "Europe/Athens")
        let utc = makeBuilder(timeZone: "UTC")

        XCTAssertEqual(athens.dayLabel(athensMidnight), "Today")
        XCTAssertEqual(utc.dayLabel(athensMidnight), "Yesterday")
        XCTAssertEqual(athens.dayLabel(athensMidnight - 24 * 60 * minute), "Yesterday")
        XCTAssertFalse(athens.dayLabel(athensMidnight - 3 * 24 * 60 * minute).contains("day"))
    }

    func testSeparatorsKeepCoreOrderAndBreakRunsAcrossMidnight() {
        let midnight = nowMs - 10 * 60 * minute
        let items: [TimelineItem] = [
            .dateSeparator(dayStartMs: midnight - 24 * 60 * minute),
            message("a", alice, at: midnight - 2 * minute),
            .dateSeparator(dayStartMs: midnight),
            message("b", alice, at: midnight + minute),
        ]

        let built = makeBuilder().build(items, isGroup: true, typingText: nil)

        XCTAssertEqual(built.map(\.id), ["day:\(midnight - 24 * 60 * minute)", "msg:a", "day:\(midnight)", "msg:b"])
        XCTAssertEqual(built[0].kind, .dateSeparator("Yesterday"))
        XCTAssertEqual(built[2].kind, .dateSeparator("Today"))
        let messageRows = rows(built)
        XCTAssertEqual(messageRows.map(\.hasTail), [true, true])
        XCTAssertEqual(messageRows.map(\.isFirstInRun), [true, true])
        XCTAssertEqual(messageRows.map(\.senderName), ["Alice", "Alice"])
    }

    func testRunGroupingBySenderAndFiveMinuteGap() {
        let start = nowMs - 60 * minute
        let items: [TimelineItem] = [
            message("1", alice, at: start),
            message("2", alice, at: start + 5 * minute),
            message("3", alice, at: start + 11 * minute),
            message("4", bob, at: start + 12 * minute),
            .membershipChange(userName: "Carol", change: .added, atMs: start + 13 * minute),
            message("5", bob, at: start + 14 * minute),
        ]

        let built = makeBuilder().build(items, isGroup: true, typingText: nil)
        let messageRows = rows(built)

        XCTAssertEqual(messageRows.map(\.isFirstInRun), [true, false, true, true, true])
        XCTAssertEqual(messageRows.map(\.hasTail), [false, true, true, true, true])
        XCTAssertEqual(messageRows.map(\.senderName), ["Alice", nil, "Alice", "Bob", "Bob"])
        XCTAssertEqual(built[4].kind, .membership("Carol was added"))
    }

    func testSenderNamesOnlyInGroupsAndNeverForOwnMessages() {
        let items: [TimelineItem] = [
            message("1", alice, at: nowMs),
            message("2", bob, at: nowMs + minute, isOwn: true, sendState: .sent),
        ]

        XCTAssertEqual(rows(makeBuilder().build(items, isGroup: false, typingText: nil)).map(\.senderName), [nil, nil])
        XCTAssertEqual(
            rows(makeBuilder().build(items, isGroup: true, typingText: nil)).map(\.senderName), ["Alice", nil])
    }

    func testReplyReactionsEditedAndDeleted() {
        let reply = ReplyPreview(messageId: "0", senderName: "Bob", text: "Ahoy")
        let reactions = [ReactionGroup(emoji: "👍", count: 2, own: true)]
        let items: [TimelineItem] = [
            message("1", alice, at: nowMs, replyTo: reply, reactions: reactions, edited: true),
            message(
                "2", alice, at: nowMs + minute, content: .deleted, replyTo: reply, reactions: reactions, edited: true),
            message("3", alice, at: nowMs + 2 * minute, content: .unsupported),
        ]

        let messageRows = rows(makeBuilder().build(items, isGroup: false, typingText: nil))

        XCTAssertEqual(messageRows[0].body, .text("hi"))
        XCTAssertEqual(messageRows[0].reply, reply)
        XCTAssertEqual(messageRows[0].reactions, reactions)
        XCTAssertTrue(messageRows[0].isEdited)
        XCTAssertEqual(messageRows[1].body, .placeholder("This message was deleted"))
        XCTAssertNil(messageRows[1].reply)
        XCTAssertEqual(messageRows[1].reactions, [])
        XCTAssertFalse(messageRows[1].isEdited)
        guard case .placeholder = messageRows[2].body else { return XCTFail("unsupported should be a placeholder") }
    }

    func testMediaBodiesAndTime() {
        let media = MediaRef(chatId: "chat", messageId: "1", mime: "application/pdf", size: 2048, hasThumbnail: false)
        let items: [TimelineItem] = [
            message("1", alice, at: nowMs, content: .file(media: media, fileName: nil, caption: "Plan")),
            message("2", alice, at: nowMs, content: .image(media: media, width: 400, height: 300, caption: nil)),
        ]

        let messageRows = rows(makeBuilder(timeZone: "Europe/Athens").build(items, isGroup: false, typingText: nil))

        guard case .file(_, let fileName, let sizeText, let caption) = messageRows[0].body else {
            return XCTFail("expected a file body")
        }
        XCTAssertEqual(fileName, "File")
        XCTAssertFalse(sizeText.isEmpty)
        XCTAssertEqual(caption, "Plan")
        XCTAssertEqual(messageRows[1].body, .image(media: media, width: 400, height: 300, caption: nil))
        XCTAssertEqual(messageRows[0].timeText, "13:00")
    }

    func testStatusOnlyForOwnMessages() {
        let states: [SendState] = [.pending, .sent, .delivered, .read, .failed(reason: "x")]
        var items = states.enumerated().map { index, state in
            message("own\(index)", bob, at: nowMs, isOwn: true, sendState: state)
        }
        items.append(message("other", alice, at: nowMs))
        items.append(message("gone", bob, at: nowMs, content: .deleted, isOwn: true, sendState: .read))

        let statuses = rows(makeBuilder().build(items, isGroup: false, typingText: nil)).map(\.status)

        XCTAssertEqual(statuses, [.sending, .sent, .delivered, .read, .failed(reason: "x"), nil, nil])
    }

    func testTypingRowAtBottom() {
        let built = makeBuilder().build(
            [message("1", alice, at: nowMs)], isGroup: false, typingText: "Alice is typing…")

        XCTAssertEqual(built.last?.id, TimelineDisplayItem.typingId)
        XCTAssertEqual(built.last?.kind, .typing("Alice is typing…"))
    }

    func testTypingText() {
        XCTAssertNil(TimelineItemBuilder.typingText(names: []))
        XCTAssertEqual(TimelineItemBuilder.typingText(names: ["Alice"]), "Alice is typing…")
        XCTAssertEqual(TimelineItemBuilder.typingText(names: ["Alice", "Bob"]), "Alice and Bob are typing…")
        XCTAssertEqual(TimelineItemBuilder.typingText(names: ["Alice", "Bob", "Carol"]), "3 people are typing…")
    }

    func testDuplicateIdsAreMadeUnique() {
        let items: [TimelineItem] = [message("1", alice, at: nowMs), message("1", alice, at: nowMs)]

        XCTAssertEqual(makeBuilder().build(items, isGroup: false, typingText: nil).map(\.id), ["msg:1", "msg:1#2"])
    }
}

final class TimelineChangeSetTests: XCTestCase {
    private let builder = makeBuilder()

    private func build(_ items: [TimelineItem], typing: String? = nil) -> [TimelineDisplayItem] {
        builder.build(items, isGroup: false, typingText: typing)
    }

    func testInsertAtBottomIsNotPrepend() {
        let old = build([.dateSeparator(dayStartMs: 0), message("1", alice, at: nowMs)], typing: "Alice is typing…")
        let new = build(
            [.dateSeparator(dayStartMs: 0), message("1", alice, at: nowMs), message("2", bob, at: nowMs)],
            typing: "Alice is typing…")

        let change = TimelineChangeSet(from: old, to: new)

        XCTAssertEqual(change, TimelineChangeSet(insertedIds: ["msg:2"]))
    }

    func testUpdateReloadsChangedRowsOnly() {
        let old = build([
            message("1", alice, at: nowMs), message("2", bob, at: nowMs, isOwn: true, sendState: .pending),
        ])
        let new = build([message("1", alice, at: nowMs), message("2", bob, at: nowMs, isOwn: true, sendState: .sent)])

        XCTAssertEqual(TimelineChangeSet(from: old, to: new), TimelineChangeSet(reloadedIds: ["msg:2"]))
    }

    func testRunChangeReloadsNeighbour() {
        let old = build([message("1", alice, at: nowMs)])
        let new = build([message("1", alice, at: nowMs), message("2", alice, at: nowMs + minute)])

        let change = TimelineChangeSet(from: old, to: new)

        XCTAssertEqual(change.insertedIds, ["msg:2"])
        XCTAssertEqual(change.reloadedIds, ["msg:1"], "the tail moves to the new message")
    }

    func testRemove() {
        let old = build([message("1", alice, at: nowMs), message("2", bob, at: nowMs)], typing: "Bob is typing…")
        let new = build([message("1", alice, at: nowMs)])

        XCTAssertEqual(
            TimelineChangeSet(from: old, to: new),
            TimelineChangeSet(deletedIds: ["msg:2", TimelineDisplayItem.typingId]))
    }

    func testReset() {
        let items = build([message("1", alice, at: nowMs)])

        let change = TimelineChangeSet(from: items, to: items, isReset: true)

        XCTAssertTrue(change.isReset)
        XCTAssertFalse(change.isEmpty)
        XCTAssertEqual(change.insertedIds, [])
    }

    func testPrependSameDayKeepsSeparatorAndDetectsPrepend() {
        let old = build([.dateSeparator(dayStartMs: 0), message("3", alice, at: nowMs)])
        let new = build([
            .dateSeparator(dayStartMs: 0), message("1", bob, at: nowMs - 20 * minute),
            message("2", bob, at: nowMs - 19 * minute), message("3", alice, at: nowMs),
        ])

        let change = TimelineChangeSet(from: old, to: new)

        XCTAssertTrue(change.isPrepend)
        XCTAssertEqual(change.insertedIds, ["msg:1", "msg:2"])
    }

    func testPrependNewDay() {
        let old = build([.dateSeparator(dayStartMs: 86_400_000), message("3", alice, at: nowMs)])
        let new = build([
            .dateSeparator(dayStartMs: 0), message("1", bob, at: 1_000), .dateSeparator(dayStartMs: 86_400_000),
            message("3", alice, at: nowMs),
        ])

        let change = TimelineChangeSet(from: old, to: new)

        XCTAssertTrue(change.isPrepend)
        XCTAssertEqual(change.insertedIds, ["day:0", "msg:1"])
    }

    func testEmptyChange() {
        let items = build([message("1", alice, at: nowMs)])

        XCTAssertTrue(TimelineChangeSet(from: items, to: items).isEmpty)
    }
}
