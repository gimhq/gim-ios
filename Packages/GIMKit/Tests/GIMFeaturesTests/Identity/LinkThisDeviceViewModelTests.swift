import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class LinkThisDeviceViewModelTests: XCTestCase {
    private static let serverUrl = "https://gim.example.eu"

    /// What the view model reported through its `OnboardingContext`.
    @MainActor
    private final class Outcome {
        var clientRequests = 0
        var discards = 0
        var registrations: [Registration] = []
    }

    @MainActor
    private func makeViewModel(
        client: @escaping @MainActor () async throws -> any GimClientAPI
    ) -> (LinkThisDeviceViewModel, Outcome) {
        let outcome = Outcome()
        let context = OnboardingContext(
            config: ClientConfig(serverUrl: Self.serverUrl),
            client: {
                outcome.clientRequests += 1
                return try await client()
            },
            discardClient: { outcome.discards += 1 },
            recoveryKit: FakeRecoveryKitFunctions(),
            onRegistered: { outcome.registrations.append($0) })
        return (LinkThisDeviceViewModel(context: context), outcome)
    }

    /// A signed-in old device and its approve view model.
    @MainActor
    private func makeOldDevice(log: LinkCallLog) async throws -> (ApproveLinkViewModel, FakeGimClient) {
        let fake = FakeGimClient()
        _ = try await fake.createIdentity(displayName: "Sofia")
        return (ApproveLinkViewModel(client: LinkRecordingClient(fake, name: "old", log: log)), fake)
    }

    @MainActor
    func testHappyPathFollowsTheCallOrderAndSignsIn() async throws {
        let log = LinkCallLog()
        let gate = LinkGate()
        let newClient = LinkRecordingClient(name: "new", log: log, waitLinkGate: gate)
        let (viewModel, outcome) = makeViewModel { newClient }
        let (approve, _) = try await makeOldDevice(log: log)

        let starting = Task { await viewModel.start() }
        await waitUntil {
            if case .waiting = viewModel.step { true } else { false }
        }
        guard case .waiting(let qrString) = viewModel.step else { return XCTFail("\(viewModel.step)") }
        approve.linkCode = qrString
        await approve.submit()
        await gate.open()
        await starting.value

        XCTAssertEqual(viewModel.step, .comparing(sas: FakeGimClient.fakeSas))
        XCTAssertEqual(approve.sas, FakeGimClient.fakeSas)
        XCTAssertTrue(outcome.registrations.isEmpty, "not signed in before the SAS was confirmed")

        await approve.confirm(codesMatch: true)
        await viewModel.confirm(codesMatch: true)

        XCTAssertEqual(
            log.calls,
            [
                "new.startLink(\(Self.serverUrl))", "old.approveLink", "new.waitLink", "old.confirmApproval(true)",
                "new.confirmLink(true)",
            ])
        XCTAssertEqual(viewModel.step, .linked)
        XCTAssertEqual(approve.outcome, .linked)
        let registration = try XCTUnwrap(outcome.registrations.first)
        XCTAssertTrue(registration.client === newClient)
        XCTAssertEqual(registration.config, ClientConfig(serverUrl: Self.serverUrl))
        let session = try await newClient.session()
        XCTAssertEqual(registration.session, session)
        XCTAssertEqual(outcome.discards, 0)
    }

    @MainActor
    func testMismatchWipesTheDeviceAndDiscardsTheClient() async throws {
        let log = LinkCallLog()
        let newClient = LinkRecordingClient(name: "new", log: log)
        let (viewModel, outcome) = makeViewModel { newClient }
        await viewModel.start()
        XCTAssertEqual(viewModel.step, .comparing(sas: FakeGimClient.fakeSas))

        await viewModel.confirm(codesMatch: false)

        XCTAssertEqual(viewModel.step, .rejected)
        XCTAssertEqual(log.calls.last, "new.confirmLink(false)")
        XCTAssertEqual(outcome.discards, 1)
        XCTAssertTrue(outcome.registrations.isEmpty)
        let session = try await newClient.session()
        XCTAssertNil(session, "confirmLink(false) wipes the device")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testWaitLinkErrorBeforeTheBundleIsShownAndRetryWaitsOnTheSameLinkSession() async {
        let log = LinkCallLog()
        let newClient = LinkRecordingClient(name: "new", log: log, waitLinkErrors: [.Network(reason: "timed out")])
        let (viewModel, outcome) = makeViewModel { newClient }

        await viewModel.start()

        XCTAssertEqual(
            viewModel.step, .failed(message: ErrorPresenter.message(for: GimError.Network(reason: "timed out"))))

        await viewModel.start()

        XCTAssertEqual(viewModel.step, .comparing(sas: FakeGimClient.fakeSas))
        XCTAssertEqual(
            log.calls, ["new.startLink(\(Self.serverUrl))", "new.waitLink failed", "new.waitLink"],
            "no new link offer: the same QR code stays valid")
        XCTAssertEqual(outcome.clientRequests, 2, "the cached client is reused through the context")
    }

    @MainActor
    func testWaitLinkErrorAfterTheBundleIsShownAndRetryStartsANewLinkSession() async {
        let log = LinkCallLog()
        let newClient = LinkRecordingClient(
            name: "new", log: log, waitLinkErrors: [.Network(reason: "offline")], waitLinkFailsAfterBundle: true)
        let (viewModel, outcome) = makeViewModel { newClient }

        await viewModel.start()

        XCTAssertEqual(
            viewModel.step, .failed(message: ErrorPresenter.message(for: GimError.Network(reason: "offline"))))

        await viewModel.start()

        XCTAssertEqual(viewModel.step, .comparing(sas: FakeGimClient.fakeSas))
        XCTAssertEqual(
            log.calls,
            [
                "new.startLink(\(Self.serverUrl))", "new.waitLink failed", "new.waitLink used up",
                "new.startLink(\(Self.serverUrl))", "new.waitLink",
            ])
        XCTAssertEqual(outcome.clientRequests, 2, "the cached client is reused through the context")
    }

    @MainActor
    func testClientCreationErrorIsShown() async {
        let (viewModel, outcome) = makeViewModel { throw GimError.Storage(reason: "disk full") }

        await viewModel.start()

        XCTAssertEqual(viewModel.step, .failed(message: ErrorPresenter.message(for: GimError.Storage(reason: "x"))))
        XCTAssertTrue(outcome.registrations.isEmpty)
    }

    @MainActor
    func testStartDoesNothingOnceTheSasIsShown() async {
        let log = LinkCallLog()
        let (viewModel, _) = makeViewModel { LinkRecordingClient(name: "new", log: log) }
        await viewModel.start()

        await viewModel.start()

        XCTAssertEqual(viewModel.step, .comparing(sas: FakeGimClient.fakeSas))
        XCTAssertEqual(log.calls.count, 2)
    }

    @MainActor
    func testAbandonAfterTheSasRejectsTheLink() async {
        let log = LinkCallLog()
        let (viewModel, outcome) = makeViewModel { LinkRecordingClient(name: "new", log: log) }
        await viewModel.start()

        await viewModel.abandon()

        XCTAssertEqual(viewModel.step, .rejected)
        XCTAssertEqual(log.calls.last, "new.confirmLink(false)")
        XCTAssertEqual(outcome.discards, 1)
    }

    @MainActor
    func testAbandonWhileStartingDoesNothing() async {
        let (viewModel, outcome) = makeViewModel { throw GimError.Network(reason: "offline") }
        await viewModel.start()

        await viewModel.abandon()

        XCTAssertEqual(outcome.discards, 0)
    }

    @MainActor
    func testAHubThatDoesNotAdmitTheUserRefusesTheLink() async throws {
        let client = FakeGimClient()
        await client.simulateNotAdmitted(hubId: "")
        let (viewModel, outcome) = makeViewModel { client }

        await viewModel.start()

        XCTAssertEqual(viewModel.step, .failed(message: "This server doesn't accept your account."))
        XCTAssertTrue(outcome.registrations.isEmpty)
        let session = try await client.session()
        XCTAssertNil(session)
    }
}
