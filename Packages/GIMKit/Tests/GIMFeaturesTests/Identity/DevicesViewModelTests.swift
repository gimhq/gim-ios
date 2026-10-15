import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class DevicesViewModelTests: XCTestCase {
    private let session = Session(userId: "user-sofia", deviceId: "device-phone", handle: "", displayName: "Sofia")

    @MainActor
    func testLoadListsThisDeviceFirstAndExposesTheUserId() async {
        let viewModel = DevicesViewModel(client: FakeGimClient(session: session))

        await viewModel.load()

        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.userId, "user-sofia")
        XCTAssertEqual(viewModel.devices.map(\.deviceId), ["device-phone", FakeGimClient.fakeOtherDeviceId])
        XCTAssertEqual(viewModel.devices.map(\.isCurrent), [true, false])
        XCTAssertFalse(viewModel.canRevoke(viewModel.devices[0]))
        XCTAssertTrue(viewModel.canRevoke(viewModel.devices[1]))
    }

    @MainActor
    func testLoadErrorIsPresented() async {
        let viewModel = DevicesViewModel(client: FakeGimClient())

        await viewModel.load()

        XCTAssertFalse(viewModel.hasLoaded)
        XCTAssertTrue(viewModel.devices.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.NotRegistered))
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testRevokeMarksTheDeviceRevokedAndMovesItLast() async {
        let client = FakeGimClient(session: session)
        let viewModel = DevicesViewModel(client: client)
        await viewModel.load()

        await viewModel.revoke(deviceId: FakeGimClient.fakeOtherDeviceId)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.revokingDeviceId)
        let other = viewModel.devices.last
        XCTAssertEqual(other?.deviceId, FakeGimClient.fakeOtherDeviceId)
        XCTAssertEqual(other?.revoked, true)
        XCTAssertFalse(viewModel.canRevoke(other!))
    }

    @MainActor
    func testRevokeErrorIsPresentedAndKeepsTheList() async {
        let client = FakeGimClient(session: session)
        let viewModel = DevicesViewModel(client: client)
        await viewModel.load()
        try? await client.signOut()

        await viewModel.revoke(deviceId: FakeGimClient.fakeOtherDeviceId)

        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.NotRegistered))
        XCTAssertEqual(viewModel.devices.map(\.revoked), [false, false])
        XCTAssertNil(viewModel.revokingDeviceId)
        viewModel.dismissError()
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testThisDeviceAndUnknownDevicesAreNeverRevoked() async throws {
        let client = FakeGimClient(session: session)
        let viewModel = DevicesViewModel(client: client)
        await viewModel.load()

        await viewModel.revoke(deviceId: "device-phone")
        await viewModel.revoke(deviceId: "device-unknown")

        XCTAssertNil(viewModel.errorMessage)
        let devices = try await client.devices()
        XCTAssertEqual(devices.map(\.revoked), [false, false])
    }
}
