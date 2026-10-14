import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class GroupInfoViewModelTests: XCTestCase {
    @MainActor
    private func loadedGroup() async throws -> (FakeGimClient, GroupInfoViewModel) {
        let (client, _) = makeDemoClient()
        let chatId = try await client.createGroupChat(name: "Regatta", members: ["user-sofia", "user-luca"])
        let viewModel = GroupInfoViewModel(client: client, chatId: chatId)
        await viewModel.load()
        return (client, viewModel)
    }

    @MainActor
    func testLoadShowsDetails() async throws {
        let (client, _) = makeDemoClient()
        let viewModel = GroupInfoViewModel(client: client, chatId: FakeGimClient.demoGroupChatId)

        await viewModel.load()

        let details = try XCTUnwrap(viewModel.details)
        XCTAssertEqual(details.summary.title, "Aegean Crew")
        XCTAssertEqual(details.members.count, 4)
        XCTAssertTrue(viewModel.canEditMembers)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testDirectChatMembersAreReadOnly() async {
        let (client, _) = makeDemoClient()
        let viewModel = GroupInfoViewModel(client: client, chatId: FakeGimClient.demoDirectChatId)

        await viewModel.load()

        XCTAssertFalse(viewModel.canEditMembers)
    }

    @MainActor
    func testLoadErrorIsPresented() async {
        let (client, _) = makeDemoClient()
        let viewModel = GroupInfoViewModel(client: client, chatId: "missing")

        await viewModel.load()

        XCTAssertNil(viewModel.details)
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.notFound))
    }

    @MainActor
    func testAddMemberByHandleReloads() async throws {
        let (_, viewModel) = try await loadedGroup()
        XCTAssertEqual(viewModel.details?.members.count, 3)

        viewModel.memberHandle = " Nikos "
        await viewModel.addMember()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.memberHandle, "")
        XCTAssertEqual(viewModel.details?.members.map(\.user.handle), ["alex", "sofia", "luca", "nikos"])
        XCTAssertEqual(viewModel.details?.summary.memberCount, 4)
        XCTAssertFalse(viewModel.isUpdatingMembers)
    }

    @MainActor
    func testAddUnknownHandleShowsError() async throws {
        let (_, viewModel) = try await loadedGroup()

        viewModel.memberHandle = "nobody"
        await viewModel.addMember()

        XCTAssertEqual(viewModel.errorMessage, "No one uses the handle @nobody.")
        XCTAssertEqual(viewModel.memberHandle, "nobody")
        XCTAssertEqual(viewModel.details?.members.count, 3)
    }

    @MainActor
    func testRemoveMemberRequiresConfirmation() async throws {
        let (_, viewModel) = try await loadedGroup()
        let luca = try XCTUnwrap(viewModel.details?.members.first { $0.user.handle == "luca" })

        viewModel.requestRemoval(luca)
        XCTAssertEqual(viewModel.pendingRemoval, luca)
        viewModel.cancelRemoval()
        XCTAssertNil(viewModel.pendingRemoval)
        await viewModel.confirmRemoval()
        XCTAssertEqual(viewModel.details?.members.count, 3)

        viewModel.requestRemoval(luca)
        await viewModel.confirmRemoval()

        XCTAssertNil(viewModel.pendingRemoval)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.details?.members.map(\.user.handle), ["alex", "sofia"])
    }

    @MainActor
    func testSelfCannotBeRemoved() async throws {
        let (_, viewModel) = try await loadedGroup()
        let me = try XCTUnwrap(viewModel.details?.members.first { $0.isSelf })

        viewModel.requestRemoval(me)

        XCTAssertNil(viewModel.pendingRemoval)
    }

    @MainActor
    func testRemoveFailureIsPresented() async throws {
        let (client, viewModel) = try await loadedGroup()
        let luca = try XCTUnwrap(viewModel.details?.members.first { $0.user.handle == "luca" })
        try await client.removeMember(viewModel.chatId, user: luca.user.userId)

        viewModel.requestRemoval(luca)
        await viewModel.confirmRemoval()

        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.notFound))
    }
}
