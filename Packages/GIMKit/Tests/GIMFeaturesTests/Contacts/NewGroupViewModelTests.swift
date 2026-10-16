import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class NewGroupViewModelTests: XCTestCase {
    @MainActor
    private func add(_ handle: String, to viewModel: NewGroupViewModel) async {
        viewModel.memberHandle = handle
        await viewModel.addMember()
    }

    @MainActor
    func testRequiresNameAndTwoOtherMembers() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = NewGroupViewModel(client: client)
        XCTAssertEqual(viewModel.validationMessage, "Enter a group name.")
        XCTAssertFalse(viewModel.canCreate)

        viewModel.name = "   "
        XCTAssertEqual(viewModel.validationMessage, "Enter a group name.")

        viewModel.name = "Regatta"
        XCTAssertEqual(viewModel.validationMessage, "Add at least 2 members.")

        await add("sofia", to: viewModel)
        XCTAssertFalse(viewModel.canCreate)

        await add("Luca", to: viewModel)
        XCTAssertNil(viewModel.validationMessage)
        XCTAssertTrue(viewModel.canCreate)
        XCTAssertEqual(viewModel.members.map(\.handle), ["sofia", "luca"])
        XCTAssertEqual(viewModel.memberHandle, "")
    }

    @MainActor
    func testAddMemberRejectsUnknownSelfAndDuplicates() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = NewGroupViewModel(client: client)

        await add("nobody", to: viewModel)
        XCTAssertEqual(viewModel.memberError, "No one uses the handle @nobody.")
        XCTAssertEqual(viewModel.memberHandle, "nobody")

        await add("alex", to: viewModel)
        XCTAssertEqual(viewModel.memberError, "You are added to your groups automatically.")

        await add("sofia", to: viewModel)
        await add("sofia", to: viewModel)
        XCTAssertNil(viewModel.memberError)
        XCTAssertEqual(viewModel.members.map(\.handle), ["sofia"])
    }

    @MainActor
    func testRemoveMemberChip() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = NewGroupViewModel(client: client)
        await add("sofia", to: viewModel)
        await add("luca", to: viewModel)

        viewModel.removeMember("user-sofia")

        XCTAssertEqual(viewModel.members.map(\.handle), ["luca"])
    }

    @MainActor
    func testCreateReturnsNewGroup() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = NewGroupViewModel(client: client)
        let invalid = await viewModel.create()
        XCTAssertNil(invalid)

        viewModel.name = "  Regatta "
        await add("sofia", to: viewModel)
        await add("nikos", to: viewModel)
        let created = await viewModel.create()
        let chatId = try XCTUnwrap(created)

        var chats: [ChatSummary] = []
        let list = await first(try await ListenerBridge.chatList(client))
        try DiffApplier.apply(try XCTUnwrap(list), to: &chats)
        let summary = try XCTUnwrap(chats.first { $0.chatId == chatId })
        XCTAssertEqual(summary.name, "Regatta")
        XCTAssertEqual(summary.kind, .group)
        let members = try await client.chatMembers(chatId: chatId)
        XCTAssertEqual(Set(members.map(\.handle)), ["alex", "sofia", "nikos"])
        XCTAssertFalse(viewModel.isCreating)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testLookupErrorIsPresented() async {
        let viewModel = NewGroupViewModel(client: FakeGimClient())

        await add("sofia", to: viewModel)

        XCTAssertEqual(viewModel.memberError, ErrorPresenter.message(for: GimError.NotRegistered))
        XCTAssertTrue(viewModel.members.isEmpty)
    }

    @MainActor
    func testCreateWithOnlyUnreachableInviteesShowsNotFound() async {
        let (client, _) = await connected(makeDemoClient())
        for (id, handle) in [("user-kai", "kai"), ("user-mia", "mia")] {
            await client.addRemoteUser(UserProfile(userId: id, handle: handle, displayName: handle), hasDevice: false)
        }
        let viewModel = NewGroupViewModel(client: client)
        viewModel.name = "Regatta"
        await add("kai", to: viewModel)
        await add("mia", to: viewModel)

        let created = await viewModel.create()

        XCTAssertNil(created)
        XCTAssertEqual(viewModel.errorMessage, "None of these users could be found")
    }
}
