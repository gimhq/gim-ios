import Foundation
import GIMClientKit
import XCTest

@testable import GIMFeatures

final class GroupInfoViewModelTests: XCTestCase {
    @MainActor
    private func started(_ client: FakeGimClient, chatId: String) async -> GroupInfoViewModel {
        let viewModel = GroupInfoViewModel(client: client, chatId: chatId)
        viewModel.start()
        await viewModel.load()
        await eventually { viewModel.summary != nil }
        return viewModel
    }

    @MainActor
    private func startedGroup() async throws -> (FakeGimClient, GroupInfoViewModel) {
        let (client, _) = await connected(makeDemoClient())
        let chatId = try await client.createGroupChat(name: "Regatta", memberUserIds: ["user-sofia", "user-luca"])
        return (client, await started(client, chatId: chatId))
    }

    @MainActor
    private func handles(_ viewModel: GroupInfoViewModel) -> [String]? {
        viewModel.members?.map(\.user.handle)
    }

    @MainActor
    func testLoadShowsSummaryAndMembers() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await started(client, chatId: FakeGimClient.demoGroupChatId)

        XCTAssertEqual(viewModel.summary?.name, "Aegean Crew")
        XCTAssertEqual(viewModel.editedName, "Aegean Crew")
        XCTAssertEqual(handles(viewModel), ["alex", "sofia", "luca", "nikos"])
        XCTAssertEqual(viewModel.members?.filter(\.isSelf).map(\.user.userId), [FakeGimClient.demoSelfId])
        XCTAssertTrue(viewModel.canEditMembers)
        XCTAssertTrue(viewModel.canRemoveMembers)
        XCTAssertFalse(viewModel.membersUnavailable)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testDirectChatIsReadOnly() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await started(client, chatId: FakeGimClient.demoDirectChatId)

        XCTAssertFalse(viewModel.canEditMembers)
        XCTAssertFalse(viewModel.canRemoveMembers)
        XCTAssertNil(viewModel.nameToSave)
    }

    @MainActor
    func testLoadErrorIsPresented() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = GroupInfoViewModel(client: client, chatId: "missing")

        await viewModel.load()

        XCTAssertNil(viewModel.members)
        XCTAssertTrue(viewModel.membersUnavailable)
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.NotFound(reason: "chat missing")))
    }

    @MainActor
    func testAddMemberByHandleRequeries() async throws {
        let (_, viewModel) = try await startedGroup()
        XCTAssertEqual(viewModel.members?.count, 3)

        viewModel.memberHandle = " Nikos "
        await viewModel.addMember()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.memberHandle, "")
        XCTAssertEqual(handles(viewModel), ["alex", "sofia", "luca", "nikos"])
        await eventually { viewModel.summary?.memberCount == 4 }
        XCTAssertFalse(viewModel.isUpdatingMembers)
    }

    @MainActor
    func testAddUnknownHandleShowsError() async throws {
        let (_, viewModel) = try await startedGroup()

        viewModel.memberHandle = "nobody"
        await viewModel.addMember()

        XCTAssertEqual(viewModel.errorMessage, "No one uses the handle @nobody.")
        XCTAssertEqual(viewModel.memberHandle, "nobody")
        XCTAssertEqual(viewModel.members?.count, 3)
    }

    @MainActor
    func testRemoveMemberRequiresConfirmation() async throws {
        let (_, viewModel) = try await startedGroup()
        let luca = try XCTUnwrap(viewModel.members?.first { $0.user.handle == "luca" })

        viewModel.requestRemoval(luca)
        XCTAssertEqual(viewModel.pendingRemoval, luca)
        viewModel.cancelRemoval()
        XCTAssertNil(viewModel.pendingRemoval)
        await viewModel.confirmRemoval()
        XCTAssertEqual(viewModel.members?.count, 3)

        viewModel.requestRemoval(luca)
        await viewModel.confirmRemoval()

        XCTAssertNil(viewModel.pendingRemoval)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(handles(viewModel), ["alex", "sofia"])
    }

    @MainActor
    func testSelfCannotBeRemoved() async throws {
        let (_, viewModel) = try await startedGroup()
        let me = try XCTUnwrap(viewModel.members?.first { $0.isSelf })

        viewModel.requestRemoval(me)

        XCTAssertNil(viewModel.pendingRemoval)
    }

    @MainActor
    func testRemoveFailureIsPresented() async throws {
        let (client, viewModel) = try await startedGroup()
        let luca = try XCTUnwrap(viewModel.members?.first { $0.user.handle == "luca" })
        viewModel.stop()
        try await client.removeMember(chatId: viewModel.chatId, userId: luca.user.userId)

        viewModel.requestRemoval(luca)
        await viewModel.confirmRemoval()

        XCTAssertEqual(
            viewModel.errorMessage, ErrorPresenter.message(for: GimError.NotFound(reason: "member user-luca")))
    }

    @MainActor
    func testRequeriesWhenMembershipChangesElsewhere() async throws {
        let (client, viewModel) = try await startedGroup()

        try await client.addMembers(chatId: viewModel.chatId, userIds: ["user-nikos"])
        await eventually { viewModel.members?.count == 4 }

        try await client.removeMember(chatId: viewModel.chatId, userId: "user-sofia")
        await eventually { self.handles(viewModel) == ["alex", "luca", "nikos"] }
    }

    /// Waits until `count` `chatMembers` calls are held by the fake.
    @MainActor
    private func waitForHeldQueries(_ client: FakeGimClient, _ count: Int) async {
        for _ in 0..<1_000 {
            if await client.heldChatMembersCount == count { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("expected \(count) held chatMembers calls")
    }

    @MainActor
    func testOverlappingQueriesApplyInStartOrder() async throws {
        let (client, _) = await connected(makeDemoClient())
        let chatId = try await client.createGroupChat(name: "Regatta", memberUserIds: ["user-sofia", "user-luca"])
        // No listeners: this test starts every query itself.
        let viewModel = GroupInfoViewModel(client: client, chatId: chatId)
        await client.holdChatMembers(true)

        let stale = Task { await viewModel.load() }
        await waitForHeldQueries(client, 1)
        try await client.addMembers(chatId: chatId, userIds: ["user-nikos"])
        let fresh = Task { await viewModel.load() }
        await waitForHeldQueries(client, 2)
        let requery = Task { await viewModel.load() }
        await waitForHeldQueries(client, 3)

        // A finished query is applied even though a later one (like a listener-driven re-query) is still running.
        await client.releaseChatMembers(at: 1)
        await fresh.value
        XCTAssertEqual(handles(viewModel), ["alex", "sofia", "luca", "nikos"])
        XCTAssertTrue(viewModel.isLoading)

        // The query that started before the change finishes late and is dropped.
        await client.releaseChatMembers(at: 0)
        await stale.value
        XCTAssertEqual(handles(viewModel), ["alex", "sofia", "luca", "nikos"])

        await client.releaseChatMembers(at: 0)
        await requery.value
        XCTAssertEqual(handles(viewModel), ["alex", "sofia", "luca", "nikos"])
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testQueriesFinishingAfterLeavingAreIgnored() async throws {
        let (client, viewModel) = try await startedGroup()
        await client.holdChatMembers(true)
        let inFlight = Task { await viewModel.load() }
        await waitForHeldQueries(client, 1)

        await viewModel.leave()
        await client.holdChatMembers(false)
        await inFlight.value
        // Re-queries triggered by the leave itself would report the chat as missing.
        await viewModel.load()

        XCTAssertTrue(viewModel.hasLeft)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.members?.count, 3)
    }

    func testMembershipChangeDetection() {
        let change = TimelineItem.membershipChange(
            userName: "Luca", change: .added, atMs: 0, userId: "user-luca", actorUserId: "user-alex")
        let separator = TimelineItem.dateSeparator(dayStartMs: 0)
        XCTAssertTrue(GroupInfoViewModel.containsMembershipChange([.pushBack(value: change)]))
        XCTAssertTrue(GroupInfoViewModel.containsMembershipChange([.append(values: [separator, change])]))
        XCTAssertTrue(GroupInfoViewModel.containsMembershipChange([.popBack, .insert(index: 0, value: change)]))
        XCTAssertFalse(GroupInfoViewModel.containsMembershipChange([.pushBack(value: separator), .remove(index: 0)]))
    }

    @MainActor
    func testChatMembersErrorFallsBackToMemberCount() async throws {
        let (client, _) = await connected(makeDemoClient())
        let error = GimError.Network(reason: "offline")
        await client.failChatMembers(with: error)
        let viewModel = await started(client, chatId: FakeGimClient.demoGroupChatId)

        XCTAssertTrue(viewModel.membersUnavailable)
        XCTAssertNil(viewModel.members)
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: error))
        XCTAssertEqual(viewModel.summary?.memberCount, 4)
        XCTAssertTrue(viewModel.canEditMembers)
        XCTAssertFalse(viewModel.canRemoveMembers)
        viewModel.requestRemoval(GroupInfoViewModel.Member(user: FakeDemoPeers.luca, isSelf: false))
        XCTAssertNil(viewModel.pendingRemoval)

        // Adding still works; the count follows the chat list.
        viewModel.memberHandle = "kai"
        await viewModel.addMember()
        XCTAssertEqual(viewModel.errorMessage, "No one uses the handle @kai.")

        await client.failChatMembers(with: nil)
        await viewModel.load()
        XCTAssertFalse(viewModel.membersUnavailable)
        XCTAssertEqual(viewModel.members?.count, 4)
        XCTAssertTrue(viewModel.canRemoveMembers)
    }

    @MainActor
    func testChatMembersErrorKeepsTheLoadedList() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await started(client, chatId: FakeGimClient.demoGroupChatId)
        let error = GimError.Network(reason: "offline")
        await client.failChatMembers(with: error)

        await viewModel.load()

        XCTAssertFalse(viewModel.membersUnavailable)
        XCTAssertEqual(handles(viewModel), ["alex", "sofia", "luca", "nikos"])
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: error))
        XCTAssertTrue(viewModel.canRemoveMembers)
    }

    @MainActor
    func testRenameGroup() async throws {
        let (_, viewModel) = try await startedGroup()
        XCTAssertNil(viewModel.nameToSave)

        viewModel.editedName = "  Autumn Regatta "
        XCTAssertEqual(viewModel.nameToSave, "Autumn Regatta")
        await viewModel.saveName()

        await eventually { viewModel.summary?.name == "Autumn Regatta" }
        XCTAssertNil(viewModel.nameToSave)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testLeaveGroup() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let chatId = try await client.createGroupChat(name: "Regatta", memberUserIds: ["user-sofia", "user-luca"])
        let viewModel = GroupInfoViewModel(client: client, chatId: chatId)
        viewModel.start()
        await viewModel.load()
        await eventually { viewModel.summary != nil }
        XCTAssertTrue(viewModel.canLeave)

        await viewModel.leave()

        XCTAssertTrue(viewModel.hasLeft)
        XCTAssertNil(viewModel.errorMessage)
        let leavingState = try await client.chatState(chatId: chatId)
        XCTAssertEqual(leavingState, .leaving)
        await settle()
        await scheduler.advance(by: FakeGimClient.leaveCommitDelay)
        // The left chat keeps its history.
        let idsAfterLeft = try await chatIds(client)
        XCTAssertTrue(idsAfterLeft.contains(chatId))
        let state = try await client.chatState(chatId: chatId)
        XCTAssertEqual(state, .left)
    }

    @MainActor
    func testLeftGroupCanOnlyBeViewed() async throws {
        let (client, viewModel) = try await startedGroup()
        XCTAssertTrue(viewModel.canEditMembers)
        viewModel.editedName = "Autumn Regatta"
        XCTAssertNotNil(viewModel.nameToSave)

        try await client.simulateRemoval(chatId: viewModel.chatId, by: "user-sofia")

        await eventually { viewModel.summary?.state == .left }
        XCTAssertFalse(viewModel.isActive)
        XCTAssertFalse(viewModel.canEditMembers)
        XCTAssertFalse(viewModel.canRemoveMembers)
        XCTAssertFalse(viewModel.canLeave)
        XCTAssertNil(viewModel.nameToSave)
    }

    @MainActor
    func testAddMemberWithoutDeviceShowsNotFound() async throws {
        let (client, viewModel) = try await startedGroup()
        await client.addRemoteUser(UserProfile(userId: "user-kai", handle: "kai", displayName: "Kai"), hasDevice: false)

        viewModel.memberHandle = "kai"
        await viewModel.addMember()

        XCTAssertEqual(viewModel.errorMessage, "None of these users could be found")
        XCTAssertEqual(viewModel.memberHandle, "kai")
        XCTAssertEqual(viewModel.members?.count, 3)
    }

    @MainActor
    private func chatIds(_ client: FakeGimClient) async throws -> [String] {
        let list = await first(try await ListenerBridge.chatList(client))
        var chats: [ChatSummary] = []
        try DiffApplier.apply(try XCTUnwrap(list), to: &chats)
        return chats.map(\.chatId)
    }

    @MainActor
    func testAddMemberWhoseHubRefusesNamesThem() async throws {
        let (client, viewModel) = try await startedGroup()
        await client.refuseContacts(["user-nikos"])

        viewModel.memberHandle = "nikos"
        await viewModel.addMember()

        XCTAssertEqual(viewModel.errorMessage, "Nikos Papadopoulos does not accept contacts from you.")
        XCTAssertEqual(viewModel.memberHandle, "nikos")
        XCTAssertEqual(viewModel.members?.count, 3)
    }

    @MainActor
    func testMemberChangesAndLeaveRefusedByTheChatsHubAreExplained() async throws {
        let (client, viewModel) = try await startedGroup()
        await client.simulateNotAdmittedByPeer(chatId: viewModel.chatId, hubId: "hub-owner")

        viewModel.memberHandle = "nikos"
        await viewModel.addMember()

        XCTAssertEqual(viewModel.errorMessage, "This chat's hub does not accept messages from you.")
        XCTAssertEqual(viewModel.members?.count, 3)

        await viewModel.leave()

        XCTAssertEqual(viewModel.errorMessage, "This chat's hub does not accept messages from you.")
        XCTAssertFalse(viewModel.hasLeft)
        let state = try await client.chatState(chatId: viewModel.chatId)
        XCTAssertEqual(state, .active, "a refused leave keeps the chat active")
    }
}

private enum FakeDemoPeers {
    static let luca = UserProfile(userId: "user-luca", handle: "luca", displayName: "Luca Bianchi")
}
