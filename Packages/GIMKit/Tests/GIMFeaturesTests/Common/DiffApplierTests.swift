import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class DiffApplierTests: XCTestCase {
    private func chat(_ id: String, unread: UInt32 = 0) -> ChatSummary {
        ChatSummary(
            chatId: id, kind: .direct, name: id.uppercased(), avatar: nil, lastMessage: nil, unreadCount: unread,
            updatedAtMs: 0, memberCount: 2, state: .active)
    }

    private func message(_ id: String) -> TimelineItem {
        .message(
            item: MessageItem(
                messageId: id, chatId: "c", sender: UserProfile(userId: "u", displayName: "U"),
                isOwn: false, sentAtMs: 0, content: .text(body: id), replyTo: nil, reactions: [], edited: false,
                sendState: nil))
    }

    private func ids(_ items: [TimelineItem]) -> [String] {
        items.map {
            switch $0 {
            case .message(let item): item.messageId
            case .dateSeparator(let day): "day-\(day)"
            case .membershipChange(let name, _, _, _, _): "member-\(name)"
            }
        }
    }

    func testReset() throws {
        var list = [chat("a")]
        let changes = try DiffApplier.apply([ChatListDiff.reset(values: [chat("b"), chat("c")])], to: &list)
        XCTAssertEqual(list.map(\.chatId), ["b", "c"])
        XCTAssertEqual(changes, ListChangeSet(isReset: true))
        XCTAssertFalse(changes.isEmpty)
    }

    func testInsertSetRemove() throws {
        var list = [message("a"), message("b"), message("c")]
        let changes = try DiffApplier.apply(
            [
                TimelineDiff.insert(index: 3, value: message("d")),
                .set(index: 1, value: message("B")),
                .remove(index: 0),
            ], to: &list)
        XCTAssertEqual(ids(list), ["B", "c", "d"])
        XCTAssertEqual(changes.deletions, [0])
        XCTAssertEqual(changes.insertions, [2])
        XCTAssertEqual(changes.reloads, [1])
    }

    func testAppendAndPushes() throws {
        var list = [message("b")]
        let changes = try DiffApplier.apply(
            [
                TimelineDiff.append(values: [message("c"), message("d")]),
                .pushFront(value: .dateSeparator(dayStartMs: 0)),
                .pushBack(value: message("e")),
            ], to: &list)
        XCTAssertEqual(ids(list), ["day-0", "b", "c", "d", "e"])
        XCTAssertEqual(changes, ListChangeSet(insertions: [0, 2, 3, 4]))
    }

    func testPopsAndTruncate() throws {
        var list = [message("a"), message("b"), message("c"), message("d"), message("e")]
        let changes = try DiffApplier.apply(
            [TimelineDiff.popFront, .popBack, .truncate(length: 1)], to: &list)
        XCTAssertEqual(ids(list), ["b"])
        XCTAssertEqual(changes, ListChangeSet(deletions: [0, 2, 3, 4]))
    }

    func testTruncateToCurrentLengthIsANoOp() throws {
        var list = [chat("a")]
        let changes = try DiffApplier.apply([ChatListDiff.truncate(length: 1)], to: &list)
        XCTAssertEqual(list.map(\.chatId), ["a"])
        XCTAssertTrue(changes.isEmpty)
    }

    func testClearDeletesEverything() throws {
        var list = [chat("a"), chat("b")]
        let changes = try DiffApplier.apply([ChatListDiff.clear, .pushBack(value: chat("c"))], to: &list)
        XCTAssertEqual(list.map(\.chatId), ["c"])
        XCTAssertEqual(changes, ListChangeSet(deletions: [0, 1], insertions: [0]))
    }

    func testMoveIsRemoveAndPushFront() throws {
        var list = [chat("a"), chat("b"), chat("c")]
        let changes = try DiffApplier.apply(
            [ChatListDiff.remove(index: 2), .pushFront(value: chat("c", unread: 1))], to: &list)
        XCTAssertEqual(list.map(\.chatId), ["c", "a", "b"])
        XCTAssertEqual(changes, ListChangeSet(deletions: [2], insertions: [0]))
    }

    func testSetOfInsertedItemIsOnlyAnInsertion() throws {
        var list = [message("a")]
        let changes = try DiffApplier.apply(
            [TimelineDiff.insert(index: 0, value: message("x")), .set(index: 0, value: message("y"))], to: &list)
        XCTAssertEqual(ids(list), ["y", "a"])
        XCTAssertEqual(changes, ListChangeSet(insertions: [0]))
    }

    func testSetThenRemoveIsOnlyADeletion() throws {
        var list = [chat("a"), chat("b")]
        let changes = try DiffApplier.apply(
            [ChatListDiff.set(index: 1, value: chat("b", unread: 3)), .remove(index: 1)], to: &list)
        XCTAssertEqual(list.map(\.chatId), ["a"])
        XCTAssertEqual(changes, ListChangeSet(deletions: [1]))
    }

    func testPrependedPageReportsInsertionsAtTheFront() throws {
        var list = [message("c")]
        let changes = try DiffApplier.apply(
            [TimelineDiff.insert(index: 0, value: message("a")), .insert(index: 1, value: message("b"))], to: &list)
        XCTAssertEqual(ids(list), ["a", "b", "c"])
        XCTAssertEqual(changes.insertions, [0, 1])
    }

    func testMappedDiffsApplyToRows() throws {
        var rows: [String] = []
        let diffs: [ChatListDiff] = [.reset(values: [chat("a")]), .pushBack(value: chat("b"))]
        try DiffApplier.apply(diffs.map { $0.vectorDiff.map(\.name) }, to: &rows)
        XCTAssertEqual(rows, ["A", "B"])
    }

    func testEmptyBatch() throws {
        var list = [chat("a")]
        let changes = try DiffApplier.apply([ChatListDiff](), to: &list)
        XCTAssertTrue(changes.isEmpty)
    }

    func testInvalidIndexThrowsAndLeavesListUntouched() {
        let original = [chat("a"), chat("b")]
        let cases: [(ChatListDiff, Int)] = [
            (.insert(index: 3, value: chat("x")), 3),
            (.set(index: 2, value: chat("x")), 2),
            (.remove(index: 2), 2),
            (.truncate(length: 3), 3),
        ]
        for (diff, index) in cases {
            var list = original
            XCTAssertThrowsError(
                try DiffApplier.apply([.remove(index: 0), .insert(index: 0, value: chat("z")), diff], to: &list)
            ) {
                XCTAssertEqual($0 as? DiffApplierError, .invalidIndex(diffIndex: 2, index: index, count: 2))
            }
            XCTAssertEqual(list, original)
        }
    }

    func testPopOnAnEmptyListThrows() {
        for diff in [ChatListDiff.popFront, .popBack] {
            var list = [chat("a")]
            XCTAssertThrowsError(try DiffApplier.apply([.clear, diff], to: &list)) {
                XCTAssertEqual($0 as? DiffApplierError, .invalidIndex(diffIndex: 1, index: 0, count: 0))
            }
            XCTAssertEqual(list.map(\.chatId), ["a"])
        }
    }
}
