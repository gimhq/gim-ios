import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class TimelineTextKindsTests: XCTestCase {
    func testEveryTypingKindMapsToItsEnglishText() {
        XCTAssertEqual(TimelineTypingKind.one("Alice").text, "Alice is typing…")
        XCTAssertEqual(TimelineTypingKind.two("Alice", "Bob").text, "Alice and Bob are typing…")
        XCTAssertEqual(TimelineTypingKind.many(count: 3).text, "3 people are typing…")
        XCTAssertEqual(TimelineTypingKind.one(nil).text, "Someone is typing…")
        XCTAssertEqual(TimelineTypingKind.two("Alice", nil).text, "Alice and Someone are typing…")
        XCTAssertEqual(TimelineTypingKind.two(nil, nil).text, "Someone and Someone are typing…")
    }

    func testTypingKindFollowsTheNames() {
        XCTAssertNil(TimelineItemBuilder.typingKind(names: []))
        XCTAssertEqual(TimelineItemBuilder.typingKind(names: ["Alice"]), .one("Alice"))
        XCTAssertEqual(TimelineItemBuilder.typingKind(names: ["Alice", "Bob"]), .two("Alice", "Bob"))
        XCTAssertEqual(TimelineItemBuilder.typingKind(names: [nil]), .one(nil))
        XCTAssertEqual(TimelineItemBuilder.typingKind(names: ["Alice", "Bob", "Carol", "Dan"]), .many(count: 4))
    }

    func testEveryMembershipKindMapsToItsEnglishText() {
        XCTAssertEqual(TimelineMembershipKind.youLeft.text, "You left")
        XCTAssertEqual(TimelineMembershipKind.left(user: "Bob").text, "Bob left")
        XCTAssertEqual(TimelineMembershipKind.youWereAdded.text, "You were added")
        XCTAssertEqual(TimelineMembershipKind.wasAdded(user: "Bob").text, "Bob was added")
        XCTAssertEqual(TimelineMembershipKind.youAdded(user: "Bob").text, "You added Bob")
        XCTAssertEqual(TimelineMembershipKind.addedYou(actor: "Alice").text, "Alice added you")
        XCTAssertEqual(TimelineMembershipKind.added(actor: "Alice", user: "Bob").text, "Alice added Bob")
        XCTAssertEqual(TimelineMembershipKind.youWereRemoved.text, "You were removed")
        XCTAssertEqual(TimelineMembershipKind.wasRemoved(user: "Bob").text, "Bob was removed")
        XCTAssertEqual(TimelineMembershipKind.youWereRemovedBy(actor: "Alice").text, "You were removed by Alice")
        XCTAssertEqual(TimelineMembershipKind.youRemoved(user: "Bob").text, "You removed Bob")
        XCTAssertEqual(TimelineMembershipKind.removed(actor: "Alice", user: "Bob").text, "Alice removed Bob")
    }

    func testMembershipKindFollowsTheChange() {
        let names = ["u-alice": "Alice", "u-bob": "Bob", "u-me": "Me"]
        func kind(_ change: MembershipChangeKind, user: String, actor: String?) -> TimelineMembershipKind {
            TimelineItemBuilder.membershipKind(
                userName: "Bob", change: change, userId: user, actorUserId: actor, ownUserId: "u-me", names: names)
        }
        XCTAssertEqual(kind(.left, user: "u-me", actor: "u-me"), .youLeft)
        XCTAssertEqual(kind(.left, user: "u-bob", actor: "u-bob"), .left(user: "Bob"))
        XCTAssertEqual(kind(.added, user: "u-me", actor: nil), .youWereAdded)
        XCTAssertEqual(kind(.added, user: "u-bob", actor: nil), .wasAdded(user: "Bob"))
        XCTAssertEqual(kind(.added, user: "u-bob", actor: "u-me"), .youAdded(user: "Bob"))
        XCTAssertEqual(kind(.added, user: "u-me", actor: "u-alice"), .addedYou(actor: "Alice"))
        XCTAssertEqual(kind(.added, user: "u-bob", actor: "u-alice"), .added(actor: "Alice", user: "Bob"))
        XCTAssertEqual(kind(.removed, user: "u-me", actor: nil), .youWereRemoved)
        XCTAssertEqual(kind(.removed, user: "u-bob", actor: "u-bob"), .wasRemoved(user: "Bob"))
        XCTAssertEqual(kind(.removed, user: "u-me", actor: "u-alice"), .youWereRemovedBy(actor: "Alice"))
        XCTAssertEqual(kind(.removed, user: "u-bob", actor: "u-me"), .youRemoved(user: "Bob"))
        XCTAssertEqual(kind(.removed, user: "u-bob", actor: "u-alice"), .removed(actor: "Alice", user: "Bob"))
    }

    func testEveryPlaceholderKindMapsToItsEnglishText() {
        XCTAssertEqual(MessagePlaceholderKind.deleted.text, "This message was deleted")
        XCTAssertEqual(MessagePlaceholderKind.unsupported.text, "This message can't be shown in this version")
    }

    func testPlaceholderKindFollowsTheContent() {
        let media = MediaRef(chatId: "chat", messageId: "m", mime: "image/png", size: 1, hasThumbnail: false)
        XCTAssertEqual(TimelineItemBuilder.placeholderKind(for: .deleted), .deleted)
        XCTAssertEqual(TimelineItemBuilder.placeholderKind(for: .unsupported), .unsupported)
        XCTAssertNil(TimelineItemBuilder.placeholderKind(for: .text(body: "Hi")))
        XCTAssertNil(TimelineItemBuilder.placeholderKind(for: .file(media: media, fileName: nil, caption: nil)))
    }

    func testEveryDayLabelKindMapsToItsEnglishText() {
        XCTAssertEqual(TimelineDayLabelKind.today.text, "Today")
        XCTAssertEqual(TimelineDayLabelKind.yesterday.text, "Yesterday")
        XCTAssertEqual(TimelineDayLabelKind.date("15. Oktober").text, "15. Oktober")
    }

    func testDayLabelKindFollowsTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-10-15 10:00 UTC.
        let now = Date(timeIntervalSince1970: 1_792_058_400)
        let builder = TimelineItemBuilder(calendar: calendar, locale: Locale(identifier: "en_US"), now: { now })
        let todayMs = UInt64(calendar.startOfDay(for: now).timeIntervalSince1970 * 1000)
        let dayMs: UInt64 = 24 * 60 * 60_000
        XCTAssertEqual(builder.dayLabelKind(todayMs), .today)
        XCTAssertEqual(builder.dayLabelKind(todayMs - dayMs), .yesterday)
        XCTAssertEqual(builder.dayLabelKind(todayMs - 2 * dayMs), .date(builder.dayLabel(todayMs - 2 * dayMs)))
    }
}
