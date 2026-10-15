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
        kind: ChatKind, preview: String? = "Hello", sender: String = "Sofia Marin", unread: UInt32 = 0
    ) -> ChatSummary {
        ChatSummary(
            chatId: "chat-1", kind: kind, name: "Title", avatar: avatar,
            lastMessage: preview.map {
                MessagePreview(senderName: sender, text: $0, sentAtMs: sentAtMs, isOwn: false)
            },
            unreadCount: unread, updatedAtMs: sentAtMs, memberCount: kind == .group ? 4 : 2)
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
}
