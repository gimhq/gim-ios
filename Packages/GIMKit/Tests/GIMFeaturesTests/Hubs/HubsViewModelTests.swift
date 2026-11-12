import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class HubsViewModelTests: XCTestCase {
    private let session = Session(userId: "user-kai", deviceId: "device-1", displayName: "Kai")
    private let home = FakeGimClient.hubId(forUrl: FakeGimClient.defaultHomeHubUrl)
    private let secondUrl = "https://hub2.example.eu"
    private let second = FakeGimClient.hubId(forUrl: "https://hub2.example.eu")

    private func makeClient() -> (FakeGimClient, ManualFakeScheduler) {
        let scheduler = ManualFakeScheduler()
        return (
            FakeGimClient(scheduler: scheduler, dataDirectory: makeTemporaryDirectory(), session: session), scheduler
        )
    }

    @MainActor
    private func startedViewModel(_ client: FakeGimClient) async -> HubsViewModel {
        let viewModel = HubsViewModel(client: client)
        XCTAssertTrue(viewModel.isLoading)
        viewModel.start()
        await eventually { !viewModel.hubs.isEmpty }
        return viewModel
    }

    /// Adds the hub at `url` and lets it become verified.
    @MainActor
    private func addVerified(_ client: FakeGimClient, _ scheduler: ManualFakeScheduler, _ url: String) async throws {
        _ = try await client.addHub(url: url)
        await scheduler.advance(by: FakeGimClient.hubVerifyDelay)
    }

    @MainActor
    func testListsTheHomeHubAsPrimaryVerifiedAndSignedIn() async {
        let (client, _) = makeClient()
        let viewModel = await startedViewModel(client)

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        let hub = viewModel.hubs[0]
        XCTAssertEqual(viewModel.hubs.map(\.hubId), [home])
        XCTAssertTrue(hub.isPrimary)
        XCTAssertTrue(hub.isHome)
        XCTAssertTrue(hub.signedIn)
        XCTAssertEqual(HubsViewModel.address(of: hub), "gim.example.eu")
        XCTAssertEqual(HubsViewModel.stateText(hub.state), "Connected")
        XCTAssertFalse(viewModel.canSetPrimary(hub))
        XCTAssertTrue(viewModel.canRemove(hub))
    }

    @MainActor
    func testAnAddedHubIsListedUnverifiedThenVerified() async throws {
        let (client, scheduler) = makeClient()
        let viewModel = await startedViewModel(client)

        _ = try await client.addHub(url: "\(secondUrl):8443")
        await eventually { viewModel.hubs.count == 2 }
        let added = viewModel.hubs[1]
        XCTAssertEqual(HubsViewModel.address(of: added), "hub2.example.eu:8443")
        XCTAssertEqual(HubsViewModel.stateText(added.state), "Not checked")
        XCTAssertFalse(added.signedIn)
        XCTAssertFalse(viewModel.canSetPrimary(added))

        await scheduler.advance(by: FakeGimClient.hubVerifyDelay)
        await eventually { viewModel.hubs[1].state == .verified }
        XCTAssertTrue(viewModel.hubs[1].signedIn)
        XCTAssertTrue(viewModel.canSetPrimary(viewModel.hubs[1]))
    }

    @MainActor
    func testSetPrimaryMovesTheHubFirst() async throws {
        let (client, scheduler) = makeClient()
        try await addVerified(client, scheduler, secondUrl)
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.hubs.count == 2 }

        await viewModel.setPrimary(hubId: second)

        await eventually { viewModel.hubs.first?.hubId == second }
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.busyHubId)
        XCTAssertEqual(viewModel.hubs.map(\.isPrimary), [true, false])
        XCTAssertEqual(viewModel.hubs.map(\.isHome), [false, true])
    }

    @MainActor
    func testSetPrimaryIgnoresThePrimaryAndUnknownHubs() async throws {
        let (client, _) = makeClient()
        let viewModel = await startedViewModel(client)

        await viewModel.setPrimary(hubId: home)
        await viewModel.setPrimary(hubId: "hub-unknown")

        XCTAssertNil(viewModel.errorMessage)
        let hubs = try await client.hubs()
        XCTAssertEqual(hubs.map(\.hubId), [home])
    }

    @MainActor
    func testConfirmedRemovalListsTheHubAsRemovedLast() async throws {
        let (client, scheduler) = makeClient()
        try await addVerified(client, scheduler, secondUrl)
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.hubs.count == 2 }
        await viewModel.setPrimary(hubId: second)
        await eventually { viewModel.hubs.first?.hubId == second }

        viewModel.requestRemoval(viewModel.hubs[0])
        XCTAssertEqual(viewModel.pendingRemoval?.hubId, second)
        await viewModel.confirmRemoval(of: viewModel.hubs[0])

        await eventually { viewModel.hubs.last?.state == .removed }
        XCTAssertNil(viewModel.pendingRemoval)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.hubs.map(\.hubId), [home, second])
        XCTAssertFalse(viewModel.canRemove(viewModel.hubs[1]))
        XCTAssertEqual(HubsViewModel.stateText(viewModel.hubs[1].state), "Removed")
    }

    @MainActor
    func testCancelledRemovalKeepsTheHub() async throws {
        let (client, scheduler) = makeClient()
        try await addVerified(client, scheduler, secondUrl)
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.hubs.count == 2 }

        viewModel.requestRemoval(viewModel.hubs[1])
        viewModel.cancelRemoval()

        XCTAssertNil(viewModel.pendingRemoval)
        let states = try await client.hubs().map(\.state)
        XCTAssertEqual(states, [.verified, .verified])
    }

    @MainActor
    func testAHubOwningGroupsIsRemovedOnlyAfterTheWarningIsConfirmed() async throws {
        let (client, scheduler) = makeClient()
        try await addVerified(client, scheduler, secondUrl)
        try await client.simulateOwnedGroups(hubId: second, count: 3)
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.hubs.count == 2 }

        viewModel.requestRemoval(viewModel.hubs[1])
        await viewModel.confirmRemoval(of: viewModel.hubs[1])

        let warning = try XCTUnwrap(viewModel.ownedGroupsWarning)
        XCTAssertEqual(warning.hub.hubId, second)
        XCTAssertEqual(warning.groupCount, 3)
        XCTAssertEqual(
            warning.message,
            "This server hosts 3 groups you own. Removing it doesn't move them: they keep running there, and you still"
                + " reach them through your other servers.")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.hubs[1].state, .verified)

        await viewModel.confirmOwnedGroupsRemoval(warning)

        XCTAssertNil(viewModel.ownedGroupsWarning)
        await eventually { viewModel.hubs[1].state == .removed }
    }

    @MainActor
    func testACancelledOwnedGroupsWarningKeepsTheHub() async throws {
        let (client, scheduler) = makeClient()
        try await addVerified(client, scheduler, secondUrl)
        try await client.simulateOwnedGroups(hubId: second, count: 1)
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.hubs.count == 2 }
        viewModel.requestRemoval(viewModel.hubs[1])
        await viewModel.confirmRemoval(of: viewModel.hubs[1])
        XCTAssertEqual(viewModel.ownedGroupsWarning?.message.hasPrefix("This server hosts 1 group you own."), true)

        viewModel.cancelOwnedGroupsRemoval()

        XCTAssertNil(viewModel.ownedGroupsWarning)
        let states = try await client.hubs().map(\.state)
        XCTAssertEqual(states, [.verified, .verified])
    }

    @MainActor
    func testRemovingTheHomeHubExplainsWhy() async throws {
        let (client, scheduler) = makeClient()
        try await addVerified(client, scheduler, secondUrl)
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.hubs.count == 2 }

        viewModel.requestRemoval(viewModel.hubs[0])
        await viewModel.confirmRemoval(of: viewModel.hubs[0])

        XCTAssertEqual(viewModel.notice?.title, "Can't remove your main server")
        XCTAssertEqual(viewModel.notice?.message, ErrorPresenter.message(for: GimError.HomeHub(hubId: home)))
        XCTAssertNil(viewModel.errorMessage)
        viewModel.dismissNotice()
        XCTAssertNil(viewModel.notice)
    }

    @MainActor
    func testRemovingTheLastHubExplainsWhy() async throws {
        let (client, scheduler) = makeClient()
        try await addVerified(client, scheduler, secondUrl)
        try await client.simulateHubRemovedElsewhere(hubId: home)
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.hubs.count == 2 }
        XCTAssertEqual(viewModel.hubs.map(\.hubId), [second, home])

        viewModel.requestRemoval(viewModel.hubs[0])
        await viewModel.confirmRemoval(of: viewModel.hubs[0])

        XCTAssertEqual(viewModel.notice?.title, "Can't remove your only server")
        XCTAssertEqual(viewModel.notice?.message, ErrorPresenter.message(for: GimError.LastHub(hubId: second)))
    }

    @MainActor
    func testAnUndrainedHubAsksToTryAgainLater() async throws {
        let (client, scheduler) = makeClient()
        try await addVerified(client, scheduler, "https://busy.example.eu")
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.hubs.count == 2 }

        viewModel.requestRemoval(viewModel.hubs[1])
        await viewModel.confirmRemoval(of: viewModel.hubs[1])

        XCTAssertEqual(viewModel.notice?.title, "Try again later")
        XCTAssertEqual(viewModel.notice?.message.hasSuffix("Try again later."), true)
        XCTAssertEqual(viewModel.hubs[1].state, .verified)

        viewModel.requestRemoval(viewModel.hubs[1])
        await viewModel.confirmRemoval(of: viewModel.hubs[1])
        await eventually { viewModel.hubs[1].state == .removed }
    }

    @MainActor
    func testOtherRemovalErrorsAreShownUnderTheList() async throws {
        let (client, scheduler) = makeClient()
        try await addVerified(client, scheduler, secondUrl)
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.hubs.count == 2 }
        let hub = viewModel.hubs[1]
        try await client.signOut()

        await viewModel.confirmRemoval(of: hub)

        XCTAssertNil(viewModel.notice)
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.NotRegistered))
        XCTAssertNil(viewModel.busyHubId)
        viewModel.dismissError()
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAHubWithoutUrlShowsTheStartOfItsId() {
        let hub = HubInfo(
            hubId: "b3f1c2d4e5f60718293a4b5c", url: nil, state: .unverified, priority: 1, isPrimary: false,
            isHome: false, signedIn: false)
        XCTAssertEqual(HubsViewModel.address(of: hub), "b3f1c2d4e5f6…")
        var short = hub
        short.hubId = "hub-1"
        XCTAssertEqual(HubsViewModel.address(of: short), "hub-1")
    }
}
