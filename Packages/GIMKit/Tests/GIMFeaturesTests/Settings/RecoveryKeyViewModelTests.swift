import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

/// Answers every prompt with `result` and records the reasons.
private final class StubAuthenticator: DeviceAuthenticator, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: DeviceAuthResult
    private var _reasons: [String] = []
    /// Runs while the prompt is up, before `result` is returned.
    var whilePrompting: (@MainActor () -> Void)?

    init(_ result: DeviceAuthResult) {
        _result = result
    }

    var result: DeviceAuthResult {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }
    var reasons: [String] { lock.withLock { _reasons } }

    func authenticate(reason: String) async -> DeviceAuthResult {
        lock.withLock { _reasons.append(reason) }
        if let whilePrompting { await whilePrompting() }
        return result
    }
}

final class RecoveryKeyViewModelTests: XCTestCase {
    @MainActor
    private func makeViewModel(
        client: FakeGimClient, authenticator: StubAuthenticator
    ) throws -> RecoveryKeyViewModel {
        RecoveryKeyViewModel(
            client: client, userId: try XCTUnwrap(client.userId()), recoveryKit: FakeRecoveryKitFunctions(),
            authenticator: authenticator)
    }

    @MainActor
    private func createdClient() async throws -> (FakeGimClient, String) {
        let client = FakeGimClient()
        let code = try await client.createIdentity(displayName: "Kai")
        return (client, code)
    }

    @MainActor
    func testNothingIsShownUntilTheOwnerAuthenticates() async throws {
        let (client, code) = try await createdClient()
        let authenticator = StubAuthenticator(.success)
        let viewModel = try makeViewModel(client: client, authenticator: authenticator)
        XCTAssertEqual(viewModel.state, .locked)
        XCTAssertEqual(viewModel.groupedCode, "")
        XCTAssertEqual(viewModel.kitText, "")

        await viewModel.reveal()

        XCTAssertEqual(authenticator.reasons, [RecoveryKeyViewModel.authenticationReason])
        XCTAssertEqual(viewModel.state, .shown)
        XCTAssertEqual(viewModel.groupedCode, RecoveryKit.groupedRecoveryCode(RecoveryKit.normalizedRecoveryCode(code)))
        XCTAssertEqual(
            viewModel.kitText,
            FakeRecoveryKitFunctions().formatRecoveryKit(
                userId: viewModel.userId, recoveryCode: code, labels: .localized))
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testHideDropsTheKeyUntilTheNextAuthentication() async throws {
        let (client, _) = try await createdClient()
        let authenticator = StubAuthenticator(.success)
        let viewModel = try makeViewModel(client: client, authenticator: authenticator)
        await viewModel.reveal()

        viewModel.hide()

        XCTAssertEqual(viewModel.state, .locked)
        XCTAssertEqual(viewModel.groupedCode, "")
        await viewModel.reveal()
        XCTAssertEqual(authenticator.reasons.count, 2, "showing it again asks again")
        XCTAssertEqual(viewModel.state, .shown)
    }

    @MainActor
    func testCancelledFailedAndUnavailableAuthenticationShowNothing() async throws {
        let (client, _) = try await createdClient()
        let authenticator = StubAuthenticator(.cancelled)
        let viewModel = try makeViewModel(client: client, authenticator: authenticator)

        await viewModel.reveal()
        XCTAssertEqual(viewModel.state, .locked)
        XCTAssertNil(viewModel.errorKind)

        authenticator.result = .failed
        await viewModel.reveal()
        XCTAssertEqual(viewModel.state, .locked)
        XCTAssertEqual(viewModel.errorKind, .authenticationFailed)
        XCTAssertEqual(viewModel.errorMessage, "Couldn't confirm it's you. Try again.")

        authenticator.result = .unavailable
        await viewModel.reveal()
        XCTAssertEqual(viewModel.errorKind, .noPasscode)
        XCTAssertEqual(viewModel.errorMessage, "Set a device passcode to see your recovery key.")
        XCTAssertEqual(viewModel.groupedCode, "")
    }

    @MainActor
    func testHidingWhileThePromptIsUpShowsNothingAfterIt() async throws {
        let (client, _) = try await createdClient()
        let authenticator = StubAuthenticator(.success)
        let viewModel = try makeViewModel(client: client, authenticator: authenticator)
        authenticator.whilePrompting = { viewModel.hide() }

        await viewModel.reveal()

        XCTAssertEqual(viewModel.state, .locked)
        XCTAssertEqual(viewModel.groupedCode, "")
    }

    @MainActor
    func testADeviceWithoutTheKeyOffersANewOneThatCanThenBeShown() async throws {
        let session = Session(userId: "user-kai", deviceId: "device-2", displayName: "Kai")
        let client = FakeGimClient(session: session)
        let authenticator = StubAuthenticator(.success)
        let viewModel = try makeViewModel(client: client, authenticator: authenticator)

        await viewModel.reveal()
        XCTAssertEqual(viewModel.state, .notOnThisDevice)
        XCTAssertEqual(viewModel.groupedCode, "")

        viewModel.rotation.start()
        await viewModel.rotation.rotate()
        let kit = try XCTUnwrap(viewModel.rotation.kit)
        let newCode = try XCTUnwrap(kit.code)
        kit.continueToCheck()
        kit.endingInput = FakeRecoveryKitFunctions().recoveryKeyEnding(recoveryCode: newCode)
        kit.confirm()

        XCTAssertEqual(viewModel.state, .locked, "the new key is kept here")
        await viewModel.reveal()
        XCTAssertEqual(viewModel.state, .shown)
        XCTAssertEqual(
            viewModel.groupedCode, RecoveryKit.groupedRecoveryCode(RecoveryKit.normalizedRecoveryCode(newCode)))
    }

    @MainActor
    func testAClientErrorIsShown() async throws {
        let client = FakeGimClient()
        let viewModel = RecoveryKeyViewModel(
            client: client, userId: "user-kai", recoveryKit: FakeRecoveryKitFunctions(),
            authenticator: StubAuthenticator(.success))

        await viewModel.reveal()

        XCTAssertEqual(viewModel.state, .locked)
        XCTAssertEqual(viewModel.errorKind, .error(.notRegistered))
    }
}
