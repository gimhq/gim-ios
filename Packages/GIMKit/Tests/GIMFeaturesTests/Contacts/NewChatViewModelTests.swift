import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class NewChatViewModelTests: XCTestCase {
    @MainActor
    private func makeViewModel(client: any GimClientAPI) -> (NewChatViewModel, ManualSleeper) {
        let sleeper = ManualSleeper()
        let viewModel = NewChatViewModel(client: client, sleep: { try await sleeper.sleep($0) })
        return (viewModel, sleeper)
    }

    @MainActor
    func testTypingDebouncesToOneSearch() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "s"
        viewModel.query = "so"
        viewModel.query = " Sofia "
        XCTAssertEqual(viewModel.state, .searching)

        await eventually { sleeper.pendingCount == 1 }
        await settle()
        XCTAssertEqual(sleeper.pendingCount, 1)
        XCTAssertTrue(sleeper.durations.allSatisfy { $0 == .milliseconds(300) })
        XCTAssertEqual(viewModel.state, .searching)

        sleeper.releaseAll()

        await eventually { viewModel.state != .searching }
        guard case .found(let user) = viewModel.state else { return XCTFail("Expected found, got \(viewModel.state)") }
        XCTAssertEqual(user.handle, "sofia")
    }

    @MainActor
    func testNewQueryCancelsPendingSearch() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "sofia"
        await eventually { sleeper.pendingCount == 1 }
        viewModel.query = "nobody"
        await eventually { sleeper.durations.count == 2 && sleeper.pendingCount == 1 }

        sleeper.releaseAll()

        await eventually { viewModel.state == .notFound }
    }

    @MainActor
    func testClearingQueryReturnsToIdle() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "sofia"
        await eventually { sleeper.pendingCount == 1 }
        viewModel.query = "  "

        XCTAssertEqual(viewModel.state, .idle)
        await eventually { sleeper.pendingCount == 0 }
        await settle()
        XCTAssertEqual(viewModel.state, .idle)
    }

    @MainActor
    func testSearchErrorIsPresented() async {
        let (viewModel, sleeper) = makeViewModel(client: FakeGimClient())

        viewModel.query = "sofia"
        await eventually { sleeper.pendingCount == 1 }
        sleeper.releaseAll()

        await eventually { viewModel.state == .error(ErrorPresenter.message(for: GimError.NotRegistered)) }
    }

    @MainActor
    func testStartChatReturnsDirectChat() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, sleeper) = makeViewModel(client: client)

        let none = await viewModel.startChat()
        XCTAssertNil(none)

        viewModel.query = "sofia"
        await eventually { sleeper.pendingCount == 1 }
        sleeper.releaseAll()
        await eventually { viewModel.state != .searching }

        let chatId = await viewModel.startChat()
        XCTAssertEqual(chatId, FakeGimClient.demoDirectChatId)
        XCTAssertNil(viewModel.startError)
        XCTAssertFalse(viewModel.isStarting)
    }

    @MainActor
    func testStartChatWithSelfShowsError() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "alex"
        await eventually { sleeper.pendingCount == 1 }
        sleeper.releaseAll()
        await eventually { viewModel.state != .searching }

        let chatId = await viewModel.startChat()
        XCTAssertNil(chatId)
        XCTAssertEqual(
            viewModel.startError,
            ErrorPresenter.message(for: GimError.InvalidInput(reason: "You can't start a chat with yourself")))
    }

    @MainActor
    func testStartChatWithUserWithoutDeviceShowsNotFound() async {
        let (client, _) = await connected(makeDemoClient())
        await client.addRemoteUser(UserProfile(userId: "user-kai", handle: "kai", displayName: "Kai"), hasDevice: false)
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "kai"
        await eventually { sleeper.pendingCount == 1 }
        sleeper.releaseAll()
        await eventually { viewModel.state != .searching }

        let chatId = await viewModel.startChat()
        XCTAssertNil(chatId)
        XCTAssertEqual(viewModel.startError, "User not found")
    }

    @MainActor
    func testStartChatWithAUserWhoseHubRefusesShowsTheirName() async {
        let (client, _) = await connected(makeDemoClient())
        await client.refuseContacts(["user-luca"])
        let (viewModel, sleeper) = makeViewModel(client: client)

        viewModel.query = "luca"
        await eventually { sleeper.pendingCount == 1 }
        sleeper.releaseAll()
        await eventually { viewModel.state != .searching }

        let chatId = await viewModel.startChat()
        XCTAssertNil(chatId)
        XCTAssertEqual(viewModel.startError, "Luca Bianchi does not accept contacts from you.")
    }
}
