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

    func testMembershipChangeDetection() {
        let change = TimelineItem.membershipChange(userName: "Luca", change: .added, atMs: 0)
        let separator = TimelineItem.dateSeparator(dayStartMs: 0)
        XCTAssertTrue(GroupInfoViewModel.containsMembershipChange([.pushBack(value: change)]))
        XCTAssertTrue(GroupInfoViewModel.containsMembershipChange([.append(values: [separator, change])]))
        XCTAssertTrue(GroupInfoViewModel.containsMembershipChange([.popBack, .insert(index: 0, value: change)]))
        XCTAssertFalse(GroupInfoViewModel.containsMembershipChange([.pushBack(value: separator), .remove(index: 0)]))
    }

    @MainActor
    func testNotImplementedChatMembersFallsBackToMemberCount() async throws {
        let (client, _) = await connected(makeDemoClient())
        await client.failChatMembers(with: .NotImplemented)
        let viewModel = await started(client, chatId: FakeGimClient.demoGroupChatId)

        XCTAssertTrue(viewModel.membersUnavailable)
        XCTAssertNil(viewModel.members)
        XCTAssertNil(viewModel.errorMessage)
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
        let (client, viewModel) = try await startedGroup()

        await viewModel.leave()

        XCTAssertTrue(viewModel.hasLeft)
        XCTAssertNil(viewModel.errorMessage)
        let list = await first(try await ListenerBridge.chatList(client))
        var chats: [ChatSummary] = []
        try DiffApplier.apply(try XCTUnwrap(list), to: &chats)
        XCTAssertFalse(chats.contains { $0.chatId == viewModel.chatId })
    }
}

private enum FakeDemoPeers {
    static let luca = UserProfile(userId: "user-luca", handle: "luca", displayName: "Luca Bianchi")
}
