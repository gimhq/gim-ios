import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class RestoreViewModelTests: XCTestCase {
    @MainActor
    private final class Registered {
        var registrations: [Registration] = []
    }

    @MainActor
    private func makeViewModel(
        client: @escaping @MainActor () async throws -> any GimClientAPI
    ) -> (RestoreViewModel, Registered) {
        let registered = Registered()
        let context = OnboardingContext(
            config: ClientConfig(serverUrl: "https://gim.example.eu"), client: client, discardClient: {},
            onRegistered: { registered.registrations.append($0) })
        return (RestoreViewModel(context: context), registered)
    }

    /// A fake that knows the identity of `userId` with `code`, signed out like a fresh device.
    @MainActor
    private func restorableClient() async throws -> (client: FakeGimClient, userId: String, code: String) {
        let client = FakeGimClient()
        let code = try await client.createIdentity(displayName: "Sofia")
        let userId = try XCTUnwrap(client.userId())
        try await client.signOut()
        return (client, userId, code)
    }

    @MainActor
    func testEmptyFieldsShowErrorsOnSubmitWithoutCreatingAClient() async {
        var clientRequests = 0
        let (viewModel, registered) = makeViewModel {
            clientRequests += 1
            return FakeGimClient()
        }
        XCTAssertNil(viewModel.userIdError)
        XCTAssertNil(viewModel.recoveryCodeError)
        XCTAssertFalse(viewModel.canSubmit)
        XCTAssertTrue(viewModel.revokeOthers)

        viewModel.userId = "   "
        await viewModel.submit()

        XCTAssertNotNil(viewModel.userIdError)
        XCTAssertNotNil(viewModel.recoveryCodeError)
        XCTAssertEqual(clientRequests, 0)
        XCTAssertTrue(registered.registrations.isEmpty)
    }

    @MainActor
    func testSubmitRestoresWithTrimmedInputAndSignsInAfterTheNotice() async throws {
        let (client, userId, code) = try await restorableClient()
        let (viewModel, registered) = makeViewModel { client }
        viewModel.userId = "  \(userId)\n"
        viewModel.recoveryCode = " \(code.lowercased()) \n"

        await viewModel.submit()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.showsRejoinNotice)
        XCTAssertEqual(viewModel.recoveryCode, "", "the code is dropped once used")
        XCTAssertFalse(viewModel.canSubmit)
        XCTAssertTrue(registered.registrations.isEmpty, "signs in only after the notice")

        viewModel.finish()

        let registration = try XCTUnwrap(registered.registrations.first)
        XCTAssertTrue(registration.client === client)
        XCTAssertEqual(registration.session.userId, userId)
        XCTAssertEqual(registration.config.serverUrl, "https://gim.example.eu")
        XCTAssertFalse(viewModel.showsRejoinNotice)
        viewModel.finish()
        XCTAssertEqual(registered.registrations.count, 1)
    }

    @MainActor
    func testRevokeOthersRevokesThePreviousDevices() async throws {
        let (client, userId, code) = try await restorableClient()
        let (viewModel, _) = makeViewModel { client }
        viewModel.userId = userId
        viewModel.recoveryCode = code

        await viewModel.submit()

        let devices = try await client.devices()
        XCTAssertEqual(devices.filter { !$0.isCurrent }.map(\.revoked), [true])
        XCTAssertEqual(devices.filter(\.isCurrent).map(\.revoked), [false])
    }

    @MainActor
    func testKeepingOtherDevicesLeavesThemActive() async throws {
        let (client, userId, code) = try await restorableClient()
        let (viewModel, _) = makeViewModel { client }
        viewModel.userId = userId
        viewModel.recoveryCode = code
        viewModel.revokeOthers = false

        await viewModel.submit()

        let devices = try await client.devices()
        XCTAssertEqual(devices.map(\.revoked), [false, false])
    }

    @MainActor
    func testUnknownUserShowsNotFoundMessage() async throws {
        let (client, _, code) = try await restorableClient()
        let (viewModel, registered) = makeViewModel { client }
        viewModel.userId = "user-nobody"
        viewModel.recoveryCode = code

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, "No identity with this user ID.")
        XCTAssertFalse(viewModel.showsRejoinNotice)
        XCTAssertTrue(registered.registrations.isEmpty)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    @MainActor
    func testMalformedCodeShowsTheCoreMessage() async throws {
        let (client, userId, _) = try await restorableClient()
        let (viewModel, _) = makeViewModel { client }
        viewModel.userId = userId
        viewModel.recoveryCode = "ABCD-EFGH"

        await viewModel.submit()

        XCTAssertEqual(
            viewModel.errorMessage,
            ErrorPresenter.message(for: GimError.InvalidInput(reason: "Malformed recovery code")))
        XCTAssertEqual(viewModel.recoveryCode, "ABCD-EFGH", "kept for correction")
    }

    @MainActor
    func testWrongCodeShowsMismatchMessageAndIsRetryable() async throws {
        let (client, userId, code) = try await restorableClient()
        let (viewModel, registered) = makeViewModel { client }
        viewModel.userId = userId
        // Another valid code: a different first symbol.
        viewModel.recoveryCode = (code.first == "0" ? "1" : "0") + code.dropFirst()

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, "This recovery code doesn't match this user ID.")

        viewModel.recoveryCode = code
        await viewModel.submit()
        viewModel.finish()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(registered.registrations.count, 1)
    }

    @MainActor
    func testRestoreErrorIsPresentedAndRetryRestoresOnTheSameClient() async throws {
        let (fake, userId, code) = try await restorableClient()
        let client = IdentityStubClient(fake, restoreErrors: [.Network(reason: "offline")])
        var clientRequests = 0
        let (viewModel, registered) = makeViewModel {
            clientRequests += 1
            return client
        }
        viewModel.userId = userId
        viewModel.recoveryCode = code

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.Network(reason: "offline")))
        XCTAssertEqual(viewModel.recoveryCode, code, "kept for the retry")
        XCTAssertFalse(viewModel.showsRejoinNotice)

        await viewModel.submit()
        viewModel.finish()

        XCTAssertNil(viewModel.errorMessage)
        let registration = try XCTUnwrap(registered.registrations.first)
        XCTAssertTrue(registration.client === client)
        XCTAssertEqual(registration.session.userId, userId)
        XCTAssertEqual(clientRequests, 2)
    }

    @MainActor
    func testClientCreationErrorIsPresented() async {
        let (viewModel, registered) = makeViewModel { throw GimError.Network(reason: "offline") }
        viewModel.userId = "user-sofia"
        viewModel.recoveryCode = "code"

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.Network(reason: "offline")))
        XCTAssertTrue(registered.registrations.isEmpty)
    }

    @MainActor
    func testAHubThatDoesNotAdmitTheUserRefusesTheRestore() async throws {
        let (client, userId, code) = try await restorableClient()
        await client.simulateNotAdmitted(hubId: "")
        let (viewModel, registered) = makeViewModel { client }
        viewModel.userId = userId
        viewModel.recoveryCode = code

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, "This hub does not admit your account.")
        XCTAssertFalse(viewModel.showsRejoinNotice)
        XCTAssertTrue(registered.registrations.isEmpty)
    }
}
