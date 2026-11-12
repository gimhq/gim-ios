import Foundation
import XCTest

@testable import GIMClientKit

final class FakeGimClientHubTests: XCTestCase {
    private let me = Session(userId: "user-kai", deviceId: "device-1", displayName: "Kai")
    private let homeUrl = "https://gim.example.eu"
    private let home = "hub-gim.example.eu"
    private let second = "hub-hub2.example.eu"
    private let secondUrl = "https://hub2.example.eu"

    private var scheduler = ManualFakeScheduler()
    private var handles: [TaskHandle] = []

    override func setUp() {
        super.setUp()
        scheduler = ManualFakeScheduler()
        handles = []
    }

    private func makeClient(session: Session? = nil) throws -> FakeGimClient {
        FakeGimClient(
            scheduler: scheduler, dataDirectory: try makeTemporaryDirectory(), homeHubUrl: homeUrl,
            session: session ?? me)
    }

    private func subscribe(_ client: FakeGimClient) async throws -> Recorder<[HubInfo]> {
        let recorder = Recorder<[HubInfo]>()
        handles.append(try await client.hubList(listener: recorder))
        return recorder
    }

    /// Adds the hub at `url` and waits until it is verified.
    @discardableResult
    private func addVerified(_ client: FakeGimClient, _ url: String) async throws -> HubInfo {
        let added = try await client.addHub(url: url)
        await scheduler.advance(by: FakeGimClient.hubVerifyDelay)
        return try await client.hubs().first { $0.hubId == added.hubId }!
    }

    private func homeInfo(signedIn: Bool = true) -> HubInfo {
        HubInfo(
            hubId: home, url: homeUrl, state: .verified, priority: 0, isPrimary: true, isHome: true,
            signedIn: signedIn)
    }

    // MARK: - Listing

    func testTheHomeHubIsTheConfiguredUrl() async throws {
        let client = try makeClient()

        let hubs = try await client.hubs()

        XCTAssertEqual(hubs, [homeInfo()])
        XCTAssertEqual(FakeGimClient.hubId(forUrl: "http://LocalHost:8080/api"), "hub-localhost:8080")
    }

    func testTheHomeHubIsNotSignedInWithoutASession() async throws {
        let client = FakeGimClient(scheduler: scheduler, dataDirectory: try makeTemporaryDirectory())

        let hubs = try await client.hubs()

        XCTAssertEqual(hubs.map(\.hubId), [FakeGimClient.hubId(forUrl: FakeGimClient.defaultHomeHubUrl)])
        XCTAssertEqual(hubs.map(\.signedIn), [false])
        await assertThrows(.NotRegistered) { try await client.addHub(url: secondUrl) }
    }

    func testCreateClientUsesTheServerUrlAsHomeHub() async throws {
        let hooks = MemoryHooks(dataDir: try makeTemporaryDirectory())
        let client = try await createClient(config: ClientConfig(serverUrl: "https://hub.example.it"), hooks: hooks)

        let hubs = try await client.hubs()

        XCTAssertEqual(hubs.map(\.hubId), ["hub-hub.example.it"])
        XCTAssertEqual(hubs.map(\.isHome), [true])
    }

    // MARK: - Adding

    func testAddedHubIsUnverifiedThenVerifiedAndSignedIn() async throws {
        let client = try makeClient()
        let recorder = try await subscribe(client)

        let added = try await client.addHub(url: secondUrl)

        let unverified = HubInfo(
            hubId: second, url: secondUrl, state: .unverified, priority: 1, isPrimary: false, isHome: false,
            signedIn: false)
        XCTAssertEqual(added, unverified)
        XCTAssertEqual(recorder.events, [[homeInfo()], [homeInfo(), unverified]])
        recorder.clear()

        await scheduler.advance(by: FakeGimClient.hubVerifyDelay)

        var verified = unverified
        verified.state = .verified
        verified.signedIn = true
        XCTAssertEqual(recorder.events, [[homeInfo(), verified]])
        let hubs = try await client.hubs()
        XCTAssertEqual(hubs, [homeInfo(), verified])
    }

    func testAddingAListedHubAgainChangesNothing() async throws {
        let client = try makeClient()
        let first = try await addVerified(client, secondUrl)
        let recorder = try await subscribe(client)
        recorder.clear()

        let again = try await client.addHub(url: secondUrl)

        XCTAssertEqual(again, first)
        XCTAssertEqual(recorder.events, [])
        let count = try await client.hubs().count
        XCTAssertEqual(count, 2)
    }

    func testAddedHubsAreListedLast() async throws {
        let client = try makeClient()
        try await addVerified(client, secondUrl)
        try await addVerified(client, "https://hub3.example.eu")

        let hubs = try await client.hubs()

        XCTAssertEqual(hubs.map(\.hubId), [home, second, "hub-hub3.example.eu"])
        XCTAssertEqual(hubs.map(\.priority), [0, 1, 2])
        XCTAssertEqual(hubs.map(\.isPrimary), [true, false, false])
    }

    func testAddHubRejectsInvalidUrls() async throws {
        let client = try makeClient()

        await assertThrows(.InvalidInput(reason: "url: unsupported scheme 'ftp'")) {
            try await client.addHub(url: "ftp://hub2.example.eu")
        }
        await assertThrows(.InvalidInput(reason: "url: relative URL without a base")) {
            try await client.addHub(url: "hub2.example.eu")
        }
        let hubs = try await client.hubs()
        XCTAssertEqual(hubs, [homeInfo()])
    }

    func testAddHubOfAnUnverifiedUrlThrowsHubNotVerified() async throws {
        let client = try makeClient()

        await assertThrows(.HubNotVerified(reason: "https://unverified.example.eu did not prove the hub at that URL")) {
            try await client.addHub(url: "https://unverified.example.eu")
        }
        let hubs = try await client.hubs()
        XCTAssertEqual(hubs, [homeInfo()])
    }

    func testAHubSharedByAnotherDeviceIsVerifiedOnceItsUrlIsEnteredHere() async throws {
        let client = try makeClient()
        try await client.simulateHubSharedByOtherDevice(url: secondUrl)
        await scheduler.advance(by: FakeGimClient.hubVerifyDelay)

        var shared = try await client.hubs()[1]
        XCTAssertEqual(shared.state, .unverified)
        XCTAssertEqual(shared.url, secondUrl)
        XCTAssertFalse(shared.signedIn)

        shared = try await addVerified(client, secondUrl)

        XCTAssertEqual(shared.state, .verified)
        XCTAssertTrue(shared.signedIn)
    }

    // MARK: - Primary hub

    func testSetPrimaryHubReordersTheHubs() async throws {
        let client = try makeClient()
        try await addVerified(client, secondUrl)
        let recorder = try await subscribe(client)
        recorder.clear()

        try await client.setPrimaryHub(hubId: second)

        let hubs = try await client.hubs()
        XCTAssertEqual(hubs.map(\.hubId), [second, home])
        XCTAssertEqual(hubs.map(\.priority), [0, 1])
        XCTAssertEqual(hubs.map(\.isPrimary), [true, false])
        XCTAssertEqual(hubs.map(\.isHome), [false, true])
        XCTAssertEqual(recorder.events.last, hubs)

        recorder.clear()
        try await client.setPrimaryHub(hubId: second)
        XCTAssertEqual(recorder.events, [], "nothing happens for the current primary")
    }

    func testSetPrimaryHubNeedsASessionOnEveryReprioritizedHub() async throws {
        let client = try makeClient()
        _ = try await client.addHub(url: secondUrl)

        await assertThrows(
            .InvalidInput(reason: "hub \(second) is not reachable from this device; set its URL first")
        ) {
            try await client.setPrimaryHub(hubId: second)
        }
        await assertThrows(.InvalidInput(reason: "hub hub-nowhere is not listed by the hosting record")) {
            try await client.setPrimaryHub(hubId: "hub-nowhere")
        }
        let primary = try await client.hubs().first { $0.isPrimary }?.hubId
        XCTAssertEqual(primary, home)
    }

    // MARK: - Removing

    func testRemoveHubMarksItRemoved() async throws {
        let client = try makeClient()
        try await addVerified(client, secondUrl)

        try await client.removeHub(hubId: second, confirmOwnedGroups: false)

        let hubs = try await client.hubs()
        XCTAssertEqual(hubs.map(\.hubId), [home, second])
        XCTAssertEqual(hubs.map(\.state), [.verified, .removed])
        XCTAssertEqual(hubs.map(\.signedIn), [true, false])
        await assertThrows(.InvalidInput(reason: "hub \(second) is not listed by the hosting record")) {
            try await client.removeHub(hubId: second, confirmOwnedGroups: false)
        }
    }

    func testRemovedHubCanBeAddedAgain() async throws {
        let client = try makeClient()
        try await addVerified(client, secondUrl)
        try await client.removeHub(hubId: second, confirmOwnedGroups: false)

        let added = try await addVerified(client, secondUrl)

        XCTAssertEqual(added.state, .verified)
        let count = try await client.hubs().count
        XCTAssertEqual(count, 2)
    }

    func testTheHomeHubIsNeverRemoved() async throws {
        let client = try makeClient()
        try await addVerified(client, secondUrl)
        try await client.setPrimaryHub(hubId: second)

        await assertThrows(.HomeHub(hubId: home)) {
            try await client.removeHub(hubId: home, confirmOwnedGroups: true)
        }
    }

    func testTheOnlyListedHubIsNeverRemoved() async throws {
        let client = try makeClient()
        try await addVerified(client, secondUrl)
        try await client.simulateHubRemovedElsewhere(hubId: home)

        await assertThrows(.LastHub(hubId: second)) {
            try await client.removeHub(hubId: second, confirmOwnedGroups: true)
        }
        let primary = try await client.hubs().first { $0.isPrimary }?.hubId
        XCTAssertEqual(primary, second)
    }

    func testRemovingAHubOwningGroupsNeedsConfirmation() async throws {
        let client = try makeClient()
        try await addVerified(client, secondUrl)
        try await client.simulateOwnedGroups(hubId: second, count: 3)

        await assertThrows(.HubOwnsGroups(hubId: second, groupCount: 3)) {
            try await client.removeHub(hubId: second, confirmOwnedGroups: false)
        }
        try await client.removeHub(hubId: second, confirmOwnedGroups: true)

        let state = try await client.hubs().last?.state
        XCTAssertEqual(state, .removed)
    }

    func testABusyHubIsNotDrainedOnTheFirstRemoval() async throws {
        let client = try makeClient()
        let busy = try await addVerified(client, "https://busy.example.eu")

        await assertThrows(
            .HubNotDrained(hubId: busy.hubId, reason: "1 messages and 0 commits not acknowledged yet")
        ) {
            try await client.removeHub(hubId: busy.hubId, confirmOwnedGroups: false)
        }
        try await client.removeHub(hubId: busy.hubId, confirmOwnedGroups: false)

        let state = try await client.hubs().last?.state
        XCTAssertEqual(state, .removed)
    }

    func testAddHubOfAnUnreachableUrlThrowsNetworkAndOfANonHubUrlInvalidInput() async throws {
        let client = try makeClient()

        await assertThrows(.Network(reason: "https://unreachable.example.eu: connection refused")) {
            try await client.addHub(url: "https://unreachable.example.eu")
        }
        await assertThrows(.InvalidInput(reason: "url: https://nohub.example.eu does not serve a gim hub")) {
            try await client.addHub(url: "https://nohub.example.eu")
        }
        let hubs = try await client.hubs()
        XCTAssertEqual(hubs, [homeInfo()])
    }

    func testAnOwnerHubOwnsTwoGroups() async throws {
        let client = try makeClient()
        let owner = try await addVerified(client, "https://owner.example.eu")

        await assertThrows(.HubOwnsGroups(hubId: owner.hubId, groupCount: 2)) {
            try await client.removeHub(hubId: owner.hubId, confirmOwnedGroups: false)
        }
    }

    func testSignOutForgetsTheAddedHubs() async throws {
        let client = try makeClient()
        try await addVerified(client, secondUrl)
        let recorder = try await subscribe(client)
        recorder.clear()

        try await client.signOut()

        XCTAssertEqual(recorder.events, [[homeInfo(signedIn: false)]])
    }

    func testSuspensionRefusesCallsThatNeedASessionAndKeepsTheSession() async throws {
        let client = try makeClient()
        try await addVerified(client, secondUrl)

        await client.simulateSuspension(hubId: second)

        await assertThrows(.UserSuspended(hubId: second)) { _ = try await client.devices() }
        await assertThrows(.UserSuspended(hubId: second)) {
            _ = try await client.addHub(url: "https://hub3.example.eu")
        }
        let session = try await client.session()
        XCTAssertEqual(session, me, "the session is kept")
        let hubs = try await client.hubs()
        XCTAssertEqual(hubs.map(\.hubId), [home, second])
        try await client.startSync()

        await client.simulateSuspension(hubId: nil)

        let devices = try await client.devices()
        XCTAssertFalse(devices.isEmpty)
    }

    func testNotAdmittedOnAListedHubRefusesCallsAndSendsAndKeepsTheSession() async throws {
        let client = try makeClient()
        try await addVerified(client, secondUrl)

        await client.simulateNotAdmitted(hubId: second)

        await assertThrows(.UserNotAdmitted(hubId: second)) { _ = try await client.devices() }
        let session = try await client.session()
        XCTAssertEqual(session, me, "the session is kept")
        try await client.startSync()
        let hubs = try await client.hubs()
        XCTAssertEqual(hubs.map(\.hubId), [home, second])

        await client.simulateNotAdmitted(hubId: nil)

        let devices = try await client.devices()
        XCTAssertFalse(devices.isEmpty)
    }

    func testAddingAHubThatDoesNotAdmitTheUserLeavesItUnlisted() async throws {
        let client = try makeClient()
        await client.simulateNotAdmitted(hubId: second)

        await assertThrows(.UserNotAdmitted(hubId: second)) { _ = try await client.addHub(url: secondUrl) }

        let hubs = try await client.hubs()
        XCTAssertEqual(hubs.map(\.hubId), [home])
        let devices = try await client.devices()
        XCTAssertFalse(devices.isEmpty, "an unlisted hub does not refuse the session")
    }

    func testRegistrationOnAHubThatDoesNotAdmitTheUserKeepsNothing() async throws {
        let client = FakeGimClient(
            scheduler: scheduler, dataDirectory: try makeTemporaryDirectory(), homeHubUrl: homeUrl)
        await client.simulateNotAdmitted(hubId: "")

        await assertThrows(.UserNotAdmitted(hubId: "")) { _ = try await client.createIdentity(displayName: "Kai") }
        let link = try client.startLink(hubs: [homeUrl])
        await assertThrows(.UserNotAdmitted(hubId: "")) { _ = try await client.waitLink(link: link) }
        let session = try await client.session()
        XCTAssertNil(session)

        await client.simulateNotAdmitted(hubId: nil)

        _ = try await client.createIdentity(displayName: "Kai")
    }
}
