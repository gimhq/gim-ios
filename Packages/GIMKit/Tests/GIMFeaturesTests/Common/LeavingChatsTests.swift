import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class LeavingChatsTests: XCTestCase {
    private let group = FakeGimClient.demoGroupChatId

    @MainActor
    func testLeavingUntilTheOwnLeftChangeArrives() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let leavingChats = LeavingChats(client: client, now: { fixedNow })

        try await leavingChats.leave(chatId: group)

        XCTAssertTrue(leavingChats.contains(group))
        await settle()
        XCTAssertTrue(leavingChats.contains(group), "only the own Left change ends leaving")
        await scheduler.advance(by: FakeGimClient.leaveCommitDelay)
        await eventually { !leavingChats.contains(self.group) }
    }

    @MainActor
    func testLeaveFailureKeepsTheChat() async {
        let (client, _) = await connected(makeDemoClient())
        let leavingChats = LeavingChats(client: client)

        do {
            try await leavingChats.leave(chatId: FakeGimClient.demoDirectChatId)
            XCTFail("Direct chats can't be left")
        } catch {}

        XCTAssertTrue(leavingChats.chatIds.isEmpty)
    }

    @MainActor
    func testSendRefusedWhileLeavingMarksTheChat() async throws {
        // Another LeavingChats (a previous app run) left the chat; this one learns it from the refused send.
        let (client, scheduler) = await connected(makeDemoClient())
        try await client.leaveChat(chatId: group)
        let leavingChats = LeavingChats(client: client, now: { fixedNow })
        var refusal: (any Error)?
        do {
            _ = try await client.sendText(chatId: group, body: "Hi", replyTo: nil)
        } catch {
            refusal = error
        }

        XCTAssertFalse(leavingChats.handleSendError(GimError.Network(reason: "offline"), chatId: group))
        XCTAssertFalse(leavingChats.contains(group))
        XCTAssertTrue(leavingChats.handleSendError(try XCTUnwrap(refusal), chatId: group))
        XCTAssertTrue(leavingChats.contains(group))

        await settle()
        await scheduler.advance(by: FakeGimClient.leaveCommitDelay)
        await eventually { !leavingChats.contains(self.group) }
    }

    func testLeavingRefusalDetection() {
        XCTAssertTrue(LeavingChats.isLeavingRefusal(GimError.InvalidInput(reason: "invalid state: leaving chat h/g1")))
        XCTAssertFalse(LeavingChats.isLeavingRefusal(GimError.InvalidInput(reason: "invalid state: left chat h/g1")))
        XCTAssertFalse(LeavingChats.isLeavingRefusal(GimError.NotFound(reason: "leaving chat h/g1")))
        XCTAssertFalse(LeavingChats.isLeavingRefusal(CancellationError()))
    }
}
