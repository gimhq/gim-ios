import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class DiffApplierTests: XCTestCase {
    private func chat(_ id: String, unread: UInt32 = 0) -> ChatSummary {
        ChatSummary(id: id, kind: .direct, title: id.uppercased(), unreadCount: unread, memberCount: 2)
    }

    private func message(_ id: String) -> TimelineMessage {
        TimelineMessage(
            id: id, chatId: "c", senderId: "u", senderName: "U", isOwn: false,
            timestamp: Date(timeIntervalSince1970: 0), content: .text(id))
    }

    func testReset() throws {
        var list = [chat("a")]
        let changes = try DiffApplier.apply([ChatListDiff.reset([chat("b"), chat("c")])], to: &list)
        XCTAssertEqual(list.map(\.id), ["b", "c"])
        XCTAssertEqual(changes, ListChangeSet(isReset: true))
        XCTAssertFalse(changes.isEmpty)
    }

    func testInsertUpdateRemove() throws {
        var list = [message("a"), message("b"), message("c")]
        let changes = try DiffApplier.apply(
            [
                TimelineDiff.insert(index: 3, message("d")),
                .update(index: 1, message("B")),
                .remove(index: 0),
            ], to: &list)
        XCTAssertEqual(list.map(\.id), ["B", "c", "d"])
        XCTAssertEqual(changes.deletions, [0])
        XCTAssertEqual(changes.insertions, [2])
        XCTAssertEqual(changes.reloads, [1])
    }

    func testMoveIsDeleteAndInsert() throws {
        var list = [chat("a"), chat("b"), chat("c")]
        let changes = try DiffApplier.apply(
            [ChatListDiff.remove(index: 2), .insert(index: 0, chat("c", unread: 1))], to: &list)
        XCTAssertEqual(list.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(changes, ListChangeSet(deletions: [2], insertions: [0]))
    }

    func testUpdateOfInsertedItemIsOnlyAnInsertion() throws {
        var list = [message("a")]
        let changes = try DiffApplier.apply(
            [TimelineDiff.insert(index: 0, message("x")), .update(index: 0, message("y"))], to: &list)
        XCTAssertEqual(list.map(\.id), ["y", "a"])
        XCTAssertEqual(changes, ListChangeSet(insertions: [0]))
    }

    func testUpdateThenRemoveIsOnlyADeletion() throws {
        var list = [chat("a"), chat("b")]
        let changes = try DiffApplier.apply(
            [ChatListDiff.update(index: 1, chat("b", unread: 3)), .remove(index: 1)], to: &list)
        XCTAssertEqual(list.map(\.id), ["a"])
        XCTAssertEqual(changes, ListChangeSet(deletions: [1]))
    }

    func testPrependedPageReportsInsertionsAtTheFront() throws {
        var list = [message("c")]
        let changes = try DiffApplier.apply(
            [TimelineDiff.insert(index: 0, message("a")), .insert(index: 1, message("b"))], to: &list)
        XCTAssertEqual(list.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(changes.insertions, [0, 1])
    }

    func testEmptyBatch() throws {
        var list = [chat("a")]
        let changes = try DiffApplier.apply([ChatListDiff](), to: &list)
        XCTAssertTrue(changes.isEmpty)
    }

    func testInvalidIndexThrowsAndLeavesListUntouched() {
        let original = [chat("a"), chat("b")]
        let cases: [(ChatListDiff, Int)] = [
            (.insert(index: 3, chat("x")), 3),
            (.update(index: 2, chat("x")), 2),
            (.remove(index: 2), 2),
        ]
        for (diff, index) in cases {
            var list = original
            XCTAssertThrowsError(
                try DiffApplier.apply([.remove(index: 0), .insert(index: 0, chat("z")), diff], to: &list)
            ) {
                XCTAssertEqual($0 as? DiffApplierError, .invalidIndex(diffIndex: 2, index: index, count: 2))
            }
            XCTAssertEqual(list, original)
        }
    }
}
