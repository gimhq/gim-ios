import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class ChatMuteOptionTests: XCTestCase {
    func testMutedUntilAddsTheDurationToNow() {
        let nowMs: UInt64 = 1_791_000_000_000
        XCTAssertEqual(ChatMuteOption.oneHour.mutedUntilMs(now: fixedNow), nowMs + 3_600_000)
        XCTAssertEqual(ChatMuteOption.eightHours.mutedUntilMs(now: fixedNow), nowMs + 8 * 3_600_000)
        XCTAssertEqual(ChatMuteOption.oneWeek.mutedUntilMs(now: fixedNow), nowMs + 7 * 24 * 3_600_000)
    }

    func testAlwaysMutesUntilUnmuted() {
        XCTAssertEqual(ChatMuteOption.always.mutedUntilMs(now: fixedNow), mutedForever())
    }

    func testOptionsAreListedShortestFirstWithTitles() {
        XCTAssertEqual(ChatMuteOption.allCases, [.oneHour, .eightHours, .oneWeek, .always])
        XCTAssertEqual(
            ChatMuteOption.allCases.map(\.title), ["For 1 hour", "For 8 hours", "For 1 week", "Always"])
    }
}
