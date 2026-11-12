import GIMClientKit
import GIMFeatures
import UIKit
import XCTest

@testable import GIMUI

private let bubbleSize = CGSize(width: 200, height: 60)

private func row(isOwn: Bool = false, isFirstInRun: Bool, hasTail: Bool, isEdited: Bool = false) -> TimelineMessageRow {
    let sender = UserProfile(userId: "u-alice", displayName: "Alice")
    let message = MessageItem(
        messageId: "m1", chatId: "chat", sender: sender, isOwn: isOwn, sentAtMs: 0, content: .text(body: "hi"),
        replyTo: nil, reactions: [], edited: isEdited, sendState: nil)
    return TimelineMessageRow(
        message: message, body: .text("hi"), senderName: nil, isFirstInRun: isFirstInRun, hasTail: hasTail,
        reply: nil, reactions: [], isEdited: isEdited, timeText: "10:00", status: nil)
}

/// Whether the corner at (`x`, `y`) is cut by the large radius: a point 2 pt inside it lies outside a radius-18 arc
/// but inside a radius-4 arc.
private func isRound(_ path: UIBezierPath, x: CGFloat, y: CGFloat) -> Bool {
    let inset: CGFloat = 2
    let point = CGPoint(x: x == 0 ? inset : x - inset, y: y == 0 ? inset : y - inset)
    return !path.contains(point)
}

@MainActor
final class TimelineLayoutTests: XCTestCase {
    private let width = bubbleSize.width
    private let height = bubbleSize.height

    func testBubblePathFillsItsSize() {
        let path = MessageCell.bubblePath(size: bubbleSize, isOwn: true, isFirstInRun: true, hasTail: true)
        XCTAssertEqual(path.bounds.minX, 0, accuracy: 0.01)
        XCTAssertEqual(path.bounds.minY, 0, accuracy: 0.01)
        XCTAssertEqual(path.bounds.width, width, accuracy: 0.01)
        XCTAssertEqual(path.bounds.height, height, accuracy: 0.01)
        XCTAssertTrue(path.contains(CGPoint(x: width / 2, y: height / 2)))
    }

    func testOwnBubbleSquaresTheRightSide() {
        for (isFirstInRun, hasTail) in [(true, true), (true, false), (false, false), (false, true)] {
            let path = MessageCell.bubblePath(
                size: bubbleSize, isOwn: true, isFirstInRun: isFirstInRun, hasTail: hasTail)
            XCTAssertFalse(isRound(path, x: width, y: height), "bottom right, first \(isFirstInRun) tail \(hasTail)")
            XCTAssertEqual(isRound(path, x: width, y: 0), isFirstInRun, "top right")
            XCTAssertTrue(isRound(path, x: 0, y: 0), "top left")
            XCTAssertTrue(isRound(path, x: 0, y: height), "bottom left")
        }
    }

    func testOtherBubbleSquaresTheLeftSide() {
        for (isFirstInRun, hasTail) in [(true, true), (true, false), (false, false), (false, true)] {
            let path = MessageCell.bubblePath(
                size: bubbleSize, isOwn: false, isFirstInRun: isFirstInRun, hasTail: hasTail)
            XCTAssertFalse(isRound(path, x: 0, y: height), "bottom left, first \(isFirstInRun) tail \(hasTail)")
            XCTAssertEqual(isRound(path, x: 0, y: 0), isFirstInRun, "top left")
            XCTAssertTrue(isRound(path, x: width, y: 0), "top right")
            XCTAssertTrue(isRound(path, x: width, y: height), "bottom right")
        }
    }

    func testFirstMessageOfARunGetsTheLargerTopGap() throws {
        let fonts = TimelineFonts(traits: UITraitCollection(preferredContentSizeCategory: .large))
        func bubbleTop(_ row: TimelineMessageRow) throws -> CGFloat {
            let item = TimelineDisplayItem(id: "msg:m1", kind: .message(row))
            return try XCTUnwrap(TimelineLayoutEngine.layout(item, width: 375, fonts: fonts).message).bubble.minY
        }
        let first = try bubbleTop(row(isFirstInRun: true, hasTail: false))
        let continued = try bubbleTop(row(isFirstInRun: false, hasTail: false))
        XCTAssertEqual(first, TimelineMetrics.gapAfterRun / 2)
        XCTAssertEqual(continued, TimelineMetrics.gapInRun / 2)
        XCTAssertGreaterThan(first, continued)
    }

    func testFooterOfAnEditedMessageStartsWithEdited() {
        let edited = String(localized: "edited", table: "Chat", bundle: .module)
        let footer = TimelineLayoutEngine.footerText(row(isFirstInRun: true, hasTail: true, isEdited: true))
        XCTAssertTrue(footer.hasPrefix(edited))
        XCTAssertTrue(footer.hasSuffix("10:00"))
        XCTAssertEqual(TimelineLayoutEngine.footerText(row(isFirstInRun: true, hasTail: true)), "10:00")
    }
}
