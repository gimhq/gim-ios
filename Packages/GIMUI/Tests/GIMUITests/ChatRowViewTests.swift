import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

@testable import GIMUI

final class ChatRowViewTests: XCTestCase {
    /// 2026-10-03 10:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_791_021_600)
    /// 09:05 UTC the same day, in epoch milliseconds.
    private let sentAtMs: UInt64 = 1_791_018_300_000

    private func makeRow(kind: ChatKind, unread: UInt32, isOwn: Bool, state: ChatState = .active) -> ChatRow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let formatter = RelativeDateFormatter(
            calendar: calendar, locale: Locale(identifier: "en_US_POSIX"), now: { [now] in now })
        let summary = ChatSummary(
            chatId: "chat-1", kind: kind, name: "Name", avatar: nil,
            lastMessage: MessagePreview(senderName: "Sofia Marin", text: "Hello", sentAtMs: sentAtMs, isOwn: isOwn),
            unreadCount: unread, updatedAtMs: sentAtMs, memberCount: kind == .group ? 4 : 2, state: state)
        return ChatRow(summary: summary, dateFormatter: formatter)
    }

    func testOwnReadLastMessageWithUnreadReadsEverything() throws {
        let row = makeRow(kind: .direct, unread: 3, isOwn: true)
        let time = try XCTUnwrap(row.time)
        XCTAssertTrue(time.hasPrefix("9:05"))

        let label = ChatRowView.accessibilityLabel(row: row, subtitle: "Hello", status: .read)

        XCTAssertEqual(label, "Name, Read, Hello, \(time), 3 unread")
    }

    func testLeftGroupReadsSubtitleWithoutStatus() {
        let row = makeRow(kind: .group, unread: 0, isOwn: false, state: .left)

        let label = ChatRowView.accessibilityLabel(row: row, subtitle: "You left", status: nil)

        XCTAssertTrue(label.hasPrefix("Name, You left"))
        for word in ["Read", "Delivered", "Sent", "Sending", "Not sent"] {
            XCTAssertFalse(label.contains(word), "unexpected \(word) in \(label)")
        }
    }

    func testZeroUnreadOmitsTheCount() throws {
        let row = makeRow(kind: .direct, unread: 0, isOwn: true)
        let time = try XCTUnwrap(row.time)

        let label = ChatRowView.accessibilityLabel(row: row, subtitle: "Hello", status: .sent)

        XCTAssertEqual(label, "Name, Sent, Hello, \(time)")
        XCTAssertFalse(label.contains("unread"))
    }
}
