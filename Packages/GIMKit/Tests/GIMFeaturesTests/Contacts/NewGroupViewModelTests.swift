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
        XCTAssertEqual(viewModel.memberError, "No one has the username @nobody.")
        XCTAssertEqual(viewModel.memberHandle, "nobody")

        await add("alex", to: viewModel)
        XCTAssertEqual(viewModel.memberError, "You're in your own groups automatically.")

        await add("sofia", to: viewModel)
        await add("sofia", to: viewModel)
        XCTAssertNil(viewModel.memberError)
        XCTAssertEqual(viewModel.members.map(\.handle), ["sofia"])
    }

    private static let kaiId = "u" + String(repeating: "k", count: 54) + "a"

    @MainActor
    func testAddMemberByAccountIdAddsAChipWithoutALookup() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = NewGroupViewModel(client: client)

        viewModel.memberAccountId = " \(Self.kaiId.uppercased())\n"
        await viewModel.addMemberByAccountId()
        viewModel.memberAccountId = Self.kaiId
        await viewModel.addMemberByAccountId()

        XCTAssertNil(viewModel.memberError)
        XCTAssertEqual(viewModel.memberAccountId, "")
        XCTAssertEqual(viewModel.members, [UserProfile(userId: Self.kaiId, handle: "", displayName: "")])
    }

    @MainActor
    func testAddMemberByAccountIdRejectsInvalidIdsAndSelf() async {
        let session = Session(userId: Self.kaiId, deviceId: "device-1", handle: "", displayName: "Kai")
        let viewModel = NewGroupViewModel(client: FakeGimClient(session: session))

        viewModel.memberAccountId = "sofia"
        await viewModel.addMemberByAccountId()
        XCTAssertEqual(viewModel.memberError, "This isn't a gim Account ID.")
        XCTAssertEqual(viewModel.memberAccountId, "sofia")

        viewModel.memberAccountId = Self.kaiId
        await viewModel.addMemberByAccountId()
        XCTAssertEqual(viewModel.memberError, "You're in your own groups automatically.")
        XCTAssertTrue(viewModel.members.isEmpty)
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
        XCTAssertEqual(viewModel.errorMessage, "Couldn't find anyone with these Account IDs.")
    }

    @MainActor
    func testCreateWithSomeRefusedInviteesStillAddsTheOthers() async throws {
        let (client, _) = await connected(makeDemoClient())
        await client.refuseContacts(["user-luca"])
        let viewModel = NewGroupViewModel(client: client)
        viewModel.name = "Regatta"
        await add("sofia", to: viewModel)
        await add("luca", to: viewModel)
        await add("nikos", to: viewModel)

        let created = await viewModel.create()

        let chatId = try XCTUnwrap(created, "a partial result is not a failure")
        XCTAssertNil(viewModel.errorMessage)
        let members = try await client.chatMembers(chatId: chatId)
        XCTAssertEqual(Set(members.map(\.handle)), ["alex", "sofia", "nikos"])
    }

    @MainActor
    func testCreateWithOnlyRefusedInviteesNamesThem() async {
        let (client, _) = await connected(makeDemoClient())
        await client.refuseContacts(["user-sofia", "user-luca"])
        let viewModel = NewGroupViewModel(client: client)
        viewModel.name = "Regatta"
        await add("sofia", to: viewModel)
        await add("luca", to: viewModel)

        let created = await viewModel.create()

        XCTAssertNil(created)
        XCTAssertEqual(viewModel.errorMessage, "Sofia Marin and Luca Bianchi don't accept messages from you.")
    }
}
