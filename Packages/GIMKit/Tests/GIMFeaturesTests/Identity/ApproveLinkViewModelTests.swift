import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class ApproveLinkViewModelTests: XCTestCase {
    /// A signed-in old device and a link code started on a new device.
    @MainActor
    private func makeViewModel() async throws -> (ApproveLinkViewModel, FakeGimClient, LinkCallLog, String) {
        let log = LinkCallLog()
        let fake = FakeGimClient()
        _ = try await fake.createIdentity(displayName: "Sofia")
        let qrString = try FakeGimClient().startLink(hubs: ["https://gim.example.eu"]).qrString()
        return (ApproveLinkViewModel(client: LinkRecordingClient(fake, name: "old", log: log)), fake, log, qrString)
    }

    @MainActor
    func testApproveShowsTheSasAndTheNewDevice() async throws {
        let (viewModel, fake, _, qrString) = try await makeViewModel()
        viewModel.linkCode = "  \(qrString)\n"

        await viewModel.submit()

        XCTAssertEqual(viewModel.sas, FakeGimClient.fakeSas)
        let deviceId = try XCTUnwrap(viewModel.newDeviceId)
        let devices = try await fake.devices()
        XCTAssertTrue(devices.contains { $0.deviceId == deviceId && !$0.revoked })
        XCTAssertFalse(viewModel.canApprove)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testMismatchRevokesTheNewDevice() async throws {
        let (viewModel, fake, log, qrString) = try await makeViewModel()
        await viewModel.approve(qrString: qrString)

        await viewModel.confirm(codesMatch: false)

        XCTAssertEqual(viewModel.outcome, .rejected)
        XCTAssertEqual(log.calls, ["old.approveLink", "old.confirmApproval(false)"])
        let devices = try await fake.devices()
        XCTAssertTrue(devices.contains { $0.deviceId == viewModel.newDeviceId && $0.revoked })

        await viewModel.abandon()
        XCTAssertEqual(log.calls.count, 2, "nothing left to revoke")
    }

    @MainActor
    func testMatchConfirmsTheApproval() async throws {
        let (viewModel, _, log, qrString) = try await makeViewModel()
        await viewModel.approve(qrString: qrString)

        await viewModel.confirm(codesMatch: true)
        await viewModel.abandon()

        XCTAssertEqual(viewModel.outcome, .linked)
        XCTAssertEqual(log.calls, ["old.approveLink", "old.confirmApproval(true)"])
    }

    @MainActor
    func testAbandonAfterApproveRevokesTheNewDeviceOnce() async throws {
        let (viewModel, fake, log, qrString) = try await makeViewModel()
        await viewModel.approve(qrString: qrString)
        let deviceId = try XCTUnwrap(viewModel.newDeviceId)

        await viewModel.abandon()
        await viewModel.abandon()

        XCTAssertEqual(log.calls, ["old.approveLink", "old.revokeDevice(\(deviceId))"])
        let devices = try await fake.devices()
        XCTAssertTrue(devices.contains { $0.deviceId == deviceId && $0.revoked })
        XCTAssertNil(viewModel.outcome)
    }

    @MainActor
    func testAbandonBeforeApproveDoesNothing() async throws {
        let (viewModel, _, log, _) = try await makeViewModel()

        await viewModel.abandon()

        XCTAssertTrue(log.calls.isEmpty)
    }

    @MainActor
    func testInvalidCodeShowsTheErrorAndAllowsAnotherAttempt() async throws {
        let (viewModel, _, log, qrString) = try await makeViewModel()
        viewModel.linkCode = "not a link code"

        await viewModel.submit()

        XCTAssertEqual(
            viewModel.errorMessage,
            ErrorPresenter.message(for: GimError.InvalidInput(reason: "Not a device link QR code")))
        XCTAssertNil(viewModel.sas)
        XCTAssertTrue(viewModel.canApprove)

        viewModel.linkCode = qrString
        await viewModel.submit()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.sas, FakeGimClient.fakeSas)
        XCTAssertEqual(log.calls, ["old.approveLink"])
    }

    @MainActor
    func testEmptyCodeShowsAMessageWithoutCallingTheClient() async throws {
        let (viewModel, _, log, _) = try await makeViewModel()
        viewModel.linkCode = "  "

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, "Paste the link code shown on your new device.")
        XCTAssertTrue(log.calls.isEmpty)
    }
}
