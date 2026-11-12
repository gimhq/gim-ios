import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class NewGroupViewModelTests: XCTestCase {
    private static let sofia = UserProfile(userId: accountId("s"), displayName: "Sofia Marin")
    private static let luca = UserProfile(userId: accountId("l"), displayName: "Luca Bianchi")
    private static let nikos = UserProfile(userId: accountId("n"), displayName: "Nikos Papadopoulos")

    /// The demo client (signed in as `user-alex`) that also knows Sofia, Luca and Nikos by valid Account IDs.
    @MainActor
    private func makeClient() async -> FakeGimClient {
        let (client, _) = await connected(makeDemoClient())
        for user in [Self.sofia, Self.luca, Self.nikos] { await client.addRemoteUser(user) }
        return client
    }

    @MainActor
    private func add(_ text: String, to viewModel: NewGroupViewModel) async {
        viewModel.memberAccountId = text
        await viewModel.addMember()
    }

    @MainActor
    func testRequiresNameAndTwoOtherMembers() async {
        let viewModel = NewGroupViewModel(client: await makeClient())
        XCTAssertEqual(viewModel.validationMessage, "Enter a group name.")
        XCTAssertFalse(viewModel.canCreate)

        viewModel.name = "   "
        XCTAssertEqual(viewModel.validationMessage, "Enter a group name.")

        viewModel.name = "Regatta"
        XCTAssertEqual(viewModel.validationMessage, "Add at least 2 members.")

        await add(Self.sofia.userId, to: viewModel)
        XCTAssertFalse(viewModel.canCreate)

        await add(" Account ID: \(Self.luca.userId.uppercased())\n", to: viewModel)
        XCTAssertNil(viewModel.validationMessage)
        XCTAssertTrue(viewModel.canCreate)
        XCTAssertEqual(viewModel.members.map(\.userId), [Self.sofia.userId, Self.luca.userId])
        XCTAssertEqual(viewModel.memberAccountId, "")
    }

    @MainActor
    func testAddMemberAddsAChipWithoutALookupAndIgnoresDuplicates() async {
        let viewModel = NewGroupViewModel(client: await makeClient())
        let unknown = accountId("k")

        await add(unknown, to: viewModel)
        await add(unknown, to: viewModel)

        XCTAssertNil(viewModel.memberError)
        XCTAssertEqual(viewModel.members, [UserProfile(userId: unknown, displayName: "")])
    }

    @MainActor
    func testAddMemberRejectsInvalidIdsAndSelf() async {
        let me = Session(userId: accountId("m"), deviceId: "device-1", displayName: "Me")
        let viewModel = NewGroupViewModel(client: FakeGimClient(session: me))

        await add("sofia", to: viewModel)
        XCTAssertEqual(viewModel.memberError, "This isn't a gim Account ID.")
        XCTAssertEqual(viewModel.memberAccountId, "sofia")

        await add(me.userId, to: viewModel)
        XCTAssertEqual(viewModel.memberError, "You're in your own groups automatically.")
        XCTAssertTrue(viewModel.members.isEmpty)
    }

    @MainActor
    func testEmptyFieldDoesNothing() async {
        let viewModel = NewGroupViewModel(client: await makeClient())

        await add("  ", to: viewModel)

        XCTAssertNil(viewModel.memberError)
        XCTAssertTrue(viewModel.members.isEmpty)
    }

    @MainActor
    func testRemoveMemberChip() async {
        let viewModel = NewGroupViewModel(client: await makeClient())
        await add(Self.sofia.userId, to: viewModel)
        await add(Self.luca.userId, to: viewModel)

        viewModel.removeMember(Self.sofia.userId)

        XCTAssertEqual(viewModel.members.map(\.userId), [Self.luca.userId])
    }

    @MainActor
    func testCreateReturnsNewGroup() async throws {
        let client = await makeClient()
        let viewModel = NewGroupViewModel(client: client)
        let invalid = await viewModel.create()
        XCTAssertNil(invalid)

        viewModel.name = "  Regatta "
        await add(Self.sofia.userId, to: viewModel)
        await add(Self.nikos.userId, to: viewModel)
        let created = await viewModel.create()
        let chatId = try XCTUnwrap(created)

        var chats: [ChatSummary] = []
        let list = await first(try await ListenerBridge.chatList(client))
        try DiffApplier.apply(try XCTUnwrap(list), to: &chats)
        let summary = try XCTUnwrap(chats.first { $0.chatId == chatId })
        XCTAssertEqual(summary.name, "Regatta")
        XCTAssertEqual(summary.kind, .group)
        let members = try await client.chatMembers(chatId: chatId)
        XCTAssertEqual(Set(members.map(\.userId)), [FakeGimClient.demoSelfId, Self.sofia.userId, Self.nikos.userId])
        XCTAssertFalse(viewModel.isCreating)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testCreateWithOnlyUnknownInviteesShowsNotFound() async {
        let viewModel = NewGroupViewModel(client: await makeClient())
        viewModel.name = "Regatta"
        await add(accountId("k"), to: viewModel)
        await add(accountId("q"), to: viewModel)

        let created = await viewModel.create()

        XCTAssertNil(created)
        XCTAssertEqual(viewModel.errorMessage, "Couldn't find anyone with these Account IDs.")
    }

    @MainActor
    func testCreateWithSomeRefusedInviteesStillAddsTheOthers() async throws {
        let client = await makeClient()
        await client.refuseContacts([Self.luca.userId])
        let viewModel = NewGroupViewModel(client: client)
        viewModel.name = "Regatta"
        for user in [Self.sofia, Self.luca, Self.nikos] { await add(user.userId, to: viewModel) }

        let created = await viewModel.create()

        let chatId = try XCTUnwrap(created, "a partial result is not a failure")
        XCTAssertNil(viewModel.errorMessage)
        let members = try await client.chatMembers(chatId: chatId)
        XCTAssertEqual(Set(members.map(\.userId)), [FakeGimClient.demoSelfId, Self.sofia.userId, Self.nikos.userId])
    }

    @MainActor
    func testCreateWithOnlyRefusedInviteesNamesThemByShortAccountId() async {
        let client = await makeClient()
        await client.refuseContacts([Self.sofia.userId, Self.luca.userId])
        let viewModel = NewGroupViewModel(client: client)
        viewModel.name = "Regatta"
        await add(Self.sofia.userId, to: viewModel)
        await add(Self.luca.userId, to: viewModel)

        let created = await viewModel.create()

        XCTAssertNil(created)
        XCTAssertEqual(viewModel.errorMessage, "ssssssss… and llllllll… don't accept messages from you.")
    }
}
