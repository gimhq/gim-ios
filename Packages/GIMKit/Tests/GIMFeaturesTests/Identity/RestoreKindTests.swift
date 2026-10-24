import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class RestoreKindTests: XCTestCase {
    private let validUserId = "u" + String(repeating: "abcdefghijklmnopqrstuvwxyz234567", count: 2).prefix(54) + "q"
    private let validCode = "7BQ2-K9MX-4TVA-0HZR-PC63-W8NE-1SJD-5GFY-QK2M-V7R"

    @MainActor
    private func makeViewModel(client: @escaping @MainActor () async throws -> any GimClientAPI) -> RestoreViewModel {
        let context = OnboardingContext(
            config: ClientConfig(serverUrl: "https://gim.example.eu"), client: client, discardClient: {},
            recoveryKit: FakeRecoveryKitFunctions(), onRegistered: { _ in })
        return RestoreViewModel(context: context)
    }

    func testErrorKindTexts() {
        typealias Kind = RestoreViewModel.ErrorKind
        XCTAssertEqual(
            Kind.notFound.text, "This server has no account with this Account ID. Check the ID and the server.")
        XCTAssertEqual(
            Kind.wrongCode.text, "This recovery key doesn't fit this account. Check the key and the Account ID.")
        XCTAssertEqual(Kind.userIdMissing.text, "Enter your Account ID.")
        XCTAssertEqual(Kind.recoveryCodeMissing.text, "Enter your recovery key.")
        XCTAssertEqual(
            Kind.kitNotRecognized.text,
            "We couldn't find an Account ID or recovery key here. Paste the whole kit, or type them below.")
        XCTAssertEqual(Kind.kitPartMissing.text, "Part of the kit is missing. Fill in the empty field below.")
        XCTAssertEqual(Kind.error(.hubRefused).text, "This server doesn't accept your account.")
    }

    @MainActor
    func testStaticMessagesAreTheKindTexts() async {
        XCTAssertEqual(RestoreViewModel.notFoundMessage, RestoreViewModel.ErrorKind.notFound.text)
        XCTAssertEqual(RestoreViewModel.wrongCodeMessage, RestoreViewModel.ErrorKind.wrongCode.text)
        XCTAssertEqual(RestoreViewModel.userIdMissingMessage, RestoreViewModel.ErrorKind.userIdMissing.text)
        XCTAssertEqual(
            RestoreViewModel.recoveryCodeMissingMessage, RestoreViewModel.ErrorKind.recoveryCodeMissing.text)
        XCTAssertEqual(RestoreViewModel.kitNotRecognizedMessage, RestoreViewModel.ErrorKind.kitNotRecognized.text)
        XCTAssertEqual(RestoreViewModel.kitPartMissingMessage, RestoreViewModel.ErrorKind.kitPartMissing.text)
    }

    @MainActor
    func testFieldErrorKinds() async {
        let viewModel = makeViewModel { FakeGimClient() }
        XCTAssertNil(viewModel.kitErrorKind)
        XCTAssertNil(viewModel.userIdErrorKind)
        XCTAssertNil(viewModel.recoveryCodeErrorKind)

        await viewModel.submit()
        XCTAssertEqual(viewModel.userIdErrorKind, .userIdMissing)
        XCTAssertEqual(viewModel.recoveryCodeErrorKind, .recoveryCodeMissing)

        viewModel.kitText = "Nothing to see here."
        XCTAssertEqual(viewModel.kitErrorKind, .kitNotRecognized)
        viewModel.kitText = "Recovery key: \(validCode)"
        XCTAssertEqual(viewModel.kitErrorKind, .kitPartMissing)
        XCTAssertEqual(viewModel.kitError, viewModel.kitErrorKind?.text)
        viewModel.kitText = "Account ID: \(validUserId)\nRecovery key: \(validCode)"
        XCTAssertNil(viewModel.kitErrorKind)
        XCTAssertNil(viewModel.userIdErrorKind)
        XCTAssertNil(viewModel.recoveryCodeErrorKind)
    }

    @MainActor
    func testSubmitErrorKinds() async {
        let cases: [(GimError, RestoreViewModel.ErrorKind)] = [
            (.NotFound(reason: ""), .notFound),
            (.Crypto(reason: ""), .wrongCode),
            (.UserNotAdmitted(hubId: ""), .error(.hubRefused)),
            (.Network(reason: "offline"), .error(.network)),
        ]
        for (error, kind) in cases {
            let client = IdentityStubClient(restoreErrors: [error])
            let viewModel = makeViewModel { client }
            viewModel.userId = validUserId
            viewModel.recoveryCode = validCode

            await viewModel.submit()

            XCTAssertEqual(viewModel.errorKind, kind)
            XCTAssertEqual(viewModel.errorMessage, kind.text)
        }
    }
}
