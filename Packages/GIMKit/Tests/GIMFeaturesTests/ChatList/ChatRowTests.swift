import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class ChatRowTests: XCTestCase {
    private let avatar = MediaRef(
        chatId: "chat-1", messageId: "avatar-1", mime: "image/png", size: 3, hasThumbnail: true)
    /// Ten minutes before `fixedNow`, in epoch milliseconds.
    private let sentAtMs: UInt64 = 1_791_000_000_000 - 600_000

    private func summary(
        kind: ChatKind, preview: String? = "Hello", sender: String = "Sofia Marin", unread: UInt32 = 0,
        isOwn: Bool = false, sendState: SendState? = nil, mutedUntilMs: UInt64 = 0, pinned: Bool = false,
        archived: Bool = false
    ) -> ChatSummary {
        ChatSummary(
            chatId: "chat-1", kind: kind, name: "Title", avatar: avatar,
            lastMessage: preview.map {
                MessagePreview(senderName: sender, text: $0, sentAtMs: sentAtMs, isOwn: isOwn, sendState: sendState)
            },
            unreadCount: unread, updatedAtMs: sentAtMs, memberCount: kind == .group ? 4 : 2, state: .active,
            mutedUntilMs: mutedUntilMs, pinned: pinned, archived: archived)
    }

    private func row(_ summary: ChatSummary) -> ChatRow {
        ChatRow(summary: summary, dateFormatter: makeFormatter(), now: fixedNow)
    }

    func testLastMessageStatusMapsTheOwnPreviewSendState() {
        let failure = SendState.failed(reason: "hub refused", cause: .other)
        let expected: [(SendState, MessageStatus)] = [
            (.pending, .sending), (.sent, .sent), (.delivered, .delivered), (.read, .read),
            (failure, .failed(reason: "hub refused", cause: .other)),
        ]
        for (state, status) in expected {
            XCTAssertEqual(row(summary(kind: .direct, isOwn: true, sendState: state)).lastMessageStatus, status)
        }
    }

    func testLastMessageStatusIsNilWithoutAnOwnSendState() {
        XCTAssertNil(row(summary(kind: .direct, isOwn: false, sendState: .read)).lastMessageStatus)
        XCTAssertNil(row(summary(kind: .direct, isOwn: true, sendState: nil)).lastMessageStatus)
        XCTAssertNil(row(summary(kind: .direct, preview: nil)).lastMessageStatus)
    }

    func testPinnedAndArchivedFollowTheSummary() {
        let plain = row(summary(kind: .group))
        XCTAssertFalse(plain.isPinned)
        XCTAssertFalse(plain.isArchived)
        let flagged = row(summary(kind: .group, pinned: true, archived: true))
        XCTAssertTrue(flagged.isPinned)
        XCTAssertTrue(flagged.isArchived)
    }

    func testMutedWhileTheMuteLasts() {
        let nowMs = UInt64(fixedNow.timeIntervalSince1970 * 1000)
        XCTAssertFalse(row(summary(kind: .group, mutedUntilMs: 0)).isMuted)
        XCTAssertFalse(row(summary(kind: .group, mutedUntilMs: nowMs)).isMuted, "expired at now")
        XCTAssertFalse(row(summary(kind: .group, mutedUntilMs: nowMs - 1)).isMuted)
        XCTAssertTrue(row(summary(kind: .group, mutedUntilMs: nowMs + 1)).isMuted)
        XCTAssertTrue(row(summary(kind: .group, mutedUntilMs: mutedForever())).isMuted)
    }

    func testOwnLastMessageIsFlaggedWithItsTime() {
        let row = ChatRow(summary: summary(kind: .direct, isOwn: true), dateFormatter: makeFormatter())
        XCTAssertTrue(row.lastMessageIsOwn)
        XCTAssertEqual(row.lastMessageSentAtMs, sentAtMs)
    }

    func testForeignLastMessageIsNotOwn() {
        let row = ChatRow(summary: summary(kind: .group), dateFormatter: makeFormatter())
        XCTAssertFalse(row.lastMessageIsOwn)
        XCTAssertEqual(row.lastMessageSentAtMs, sentAtMs)
    }

    func testChatWithoutMessagesHasNoOwnLastMessage() {
        let row = ChatRow(summary: summary(kind: .group, preview: nil), dateFormatter: makeFormatter())
        XCTAssertFalse(row.lastMessageIsOwn)
        XCTAssertNil(row.lastMessageSentAtMs)
    }

    func testGroupPreviewIsPrefixedWithSender() {
        XCTAssertEqual(ChatRow.preview(for: summary(kind: .group)), "Sofia Marin: Hello")
    }

    func testDirectPreviewHasNoSenderPrefix() {
        XCTAssertEqual(ChatRow.preview(for: summary(kind: .direct)), "Hello")
    }

    func testGroupPreviewWithoutSenderIsPlain() {
        XCTAssertEqual(ChatRow.preview(for: summary(kind: .group, sender: "")), "Hello")
    }

    func testMediaAndDeletedPreviewsKeepCoreText() {
        XCTAssertEqual(ChatRow.preview(for: summary(kind: .direct, preview: "Photo")), "Photo")
        XCTAssertEqual(
            ChatRow.preview(for: summary(kind: .group, preview: "File: crew.txt")), "Sofia Marin: File: crew.txt")
        XCTAssertEqual(
            ChatRow.preview(for: summary(kind: .group, preview: "Message deleted")), "Sofia Marin: Message deleted")
    }

    func testChatWithoutMessagesHasNoPreviewOrTime() {
        let row = ChatRow(summary: summary(kind: .group, preview: nil), dateFormatter: makeFormatter())
        XCTAssertNil(row.preview)
        XCTAssertNil(row.time)
    }

    func testUnreadTextIsCappedAt99() {
        XCTAssertNil(ChatRow.unreadText(for: 0))
        XCTAssertEqual(ChatRow.unreadText(for: 1), "1")
        XCTAssertEqual(ChatRow.unreadText(for: 99), "99")
        XCTAssertEqual(ChatRow.unreadText(for: 100), "99+")
        XCTAssertEqual(ChatRow.unreadText(for: 4_000), "99+")
    }

    func testRowMapsSummaryFields() {
        let formatter = makeFormatter()
        let row = ChatRow(summary: summary(kind: .group, unread: 120), dateFormatter: formatter)
        XCTAssertEqual(row.id, "chat-1")
        XCTAssertEqual(row.kind, .group)
        XCTAssertEqual(row.title, "Title")
        XCTAssertEqual(row.avatar, avatar)
        XCTAssertEqual(row.time, formatter.string(from: fixedNow.addingTimeInterval(-600)))
        XCTAssertEqual(row.unreadCount, 120)
        XCTAssertEqual(row.unreadText, "99+")
    }

    func testUserIdNamesAreShortened() {
        let userId = "u" + String(repeating: "k", count: 55)
        let summary = ChatSummary(
            chatId: "chat-1", kind: .group, name: userId, avatar: nil,
            lastMessage: MessagePreview(senderName: userId, text: "Hi", sentAtMs: sentAtMs, isOwn: false),
            unreadCount: 0, updatedAtMs: sentAtMs, memberCount: 3, state: .active)

        let row = ChatRow(summary: summary, dateFormatter: makeFormatter())

        XCTAssertEqual(row.title, "kkkkkkkk…")
        XCTAssertEqual(row.preview, "kkkkkkkk…: Hi")
    }
}
