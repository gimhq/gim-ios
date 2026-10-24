import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class BlockedUsersViewModelTests: XCTestCase {
    @MainActor
    func testLoadResolvesNamesFromChatsAndKeepsUnknownAccountIds() async throws {
        let (client, _) = await connected(makeDemoClient())
        for userId in ["user-sofia", "user-luca", "user-unknown"] {
            try await client.blockUser(userId: userId)
        }
        let viewModel = BlockedUsersViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(
            viewModel.rows,
            [
                BlockedUsersViewModel.Row(userId: "user-luca", name: "Luca Bianchi", detail: "@luca"),
                BlockedUsersViewModel.Row(userId: "user-sofia", name: "Sofia Marin", detail: "@sofia"),
                BlockedUsersViewModel.Row(userId: "user-unknown", name: nil, detail: nil),
            ])
        XCTAssertTrue(viewModel.isLoaded)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testLoadWithNoOneBlockedIsEmpty() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = BlockedUsersViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.rows, [])
        XCTAssertTrue(viewModel.isLoaded)
    }

    @MainActor
    func testUnblockRemovesTheRow() async throws {
        let (client, _) = await connected(makeDemoClient())
        try await client.blockUser(userId: "user-sofia")
        try await client.blockUser(userId: "user-luca")
        let viewModel = BlockedUsersViewModel(client: client)
        await viewModel.load()

        await viewModel.unblock(userId: "user-sofia")

        XCTAssertEqual(viewModel.rows.map(\.userId), ["user-luca"])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.unblocking.isEmpty)
        let stored = try await client.privacy()
        XCTAssertEqual(stored.blockedUserIds, ["user-luca"])
    }

    @MainActor
    func testFailedUnblockKeepsTheRowAndShowsTheError() async throws {
        let (client, _) = await connected(makeDemoClient())
        try await client.blockUser(userId: "user-sofia")
        let viewModel = BlockedUsersViewModel(client: client)
        await viewModel.load()
        await client.simulateSuspension(hubId: "")

        await viewModel.unblock(userId: "user-sofia")

        XCTAssertEqual(viewModel.rows.map(\.userId), ["user-sofia"])
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.unblocking.isEmpty)
    }

    @MainActor
    func testNamesStayUnresolvedWhenMembersCannotBeRead() async throws {
        let (client, _) = await connected(makeDemoClient())
        try await client.blockUser(userId: "user-luca")
        await client.failChatMembers(with: .Network(reason: "offline"))
        let viewModel = BlockedUsersViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.rows, [BlockedUsersViewModel.Row(userId: "user-luca", name: nil, detail: nil)])
        XCTAssertNil(viewModel.errorMessage)
    }
}
