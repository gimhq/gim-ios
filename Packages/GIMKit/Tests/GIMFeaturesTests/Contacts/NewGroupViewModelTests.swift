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
        let (client, _) = makeDemoClient()
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
        let (client, _) = makeDemoClient()
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
        let (client, _) = makeDemoClient()
        let viewModel = NewGroupViewModel(client: client)
        await add("sofia", to: viewModel)
        await add("luca", to: viewModel)

        viewModel.removeMember("user-sofia")

        XCTAssertEqual(viewModel.members.map(\.handle), ["luca"])
    }

    @MainActor
    func testCreateReturnsNewGroup() async throws {
        let (client, _) = makeDemoClient()
        let viewModel = NewGroupViewModel(client: client)
        let invalid = await viewModel.create()
        XCTAssertNil(invalid)

        viewModel.name = "  Regatta "
        await add("sofia", to: viewModel)
        await add("nikos", to: viewModel)
        let created = await viewModel.create()
        let chatId = try XCTUnwrap(created)

        let details = try await client.chatDetails(chatId)
        XCTAssertEqual(details.summary.title, "Regatta")
        XCTAssertEqual(details.summary.kind, .group)
        XCTAssertEqual(Set(details.members.map(\.user.handle)), ["alex", "sofia", "nikos"])
        XCTAssertFalse(viewModel.isCreating)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testLookupErrorIsPresented() async {
        let viewModel = NewGroupViewModel(client: FakeGimClient())

        await add("sofia", to: viewModel)

        XCTAssertEqual(viewModel.memberError, ErrorPresenter.message(for: GimError.unauthorized))
        XCTAssertTrue(viewModel.members.isEmpty)
    }
}
