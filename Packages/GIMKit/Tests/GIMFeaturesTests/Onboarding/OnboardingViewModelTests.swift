import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class OnboardingValidationTests: XCTestCase {
    func testServerUrlAcceptsHttpAndHttpsWithHost() {
        XCTAssertNil(OnboardingValidation.serverUrlError("https://gim.example.eu"))
        XCTAssertNil(OnboardingValidation.serverUrlError("http://192.168.1.20:8080"))
        XCTAssertNil(OnboardingValidation.serverUrlError("  HTTPS://gim.example.eu/  "))
    }

    func testServerUrlRejectsMissingSchemeHostOrOtherSchemes() {
        XCTAssertNotNil(OnboardingValidation.serverUrlError(""))
        XCTAssertNotNil(OnboardingValidation.serverUrlError("gim.example.eu"))
        XCTAssertNotNil(OnboardingValidation.serverUrlError("ftp://gim.example.eu"))
        XCTAssertNotNil(OnboardingValidation.serverUrlError("https://"))
        XCTAssertNotNil(OnboardingValidation.serverUrlError("https:///path"))
    }

    func testServerUrlNormalisationTrimsWhitespaceAndTrailingSlashes() {
        XCTAssertEqual(OnboardingValidation.normalizedServerUrl(" https://gim.example.eu// "), "https://gim.example.eu")
    }

    func testHandleRules() {
        XCTAssertNil(OnboardingValidation.handleError("sofia_m.2"))
        XCTAssertNil(OnboardingValidation.handleError("  Sofia "))
        XCTAssertNil(OnboardingValidation.handleError(String(repeating: "a", count: 32)))
        XCTAssertNotNil(OnboardingValidation.handleError(""))
        XCTAssertNotNil(OnboardingValidation.handleError("ab"))
        XCTAssertNotNil(OnboardingValidation.handleError(String(repeating: "a", count: 33)))
        XCTAssertNotNil(OnboardingValidation.handleError("so fia"))
        XCTAssertNotNil(OnboardingValidation.handleError("sofia-m"))
        XCTAssertNotNil(OnboardingValidation.handleError("sofía"))
    }

    func testHandleNormalisationLowercasesAndTrims() {
        XCTAssertEqual(OnboardingValidation.normalizedHandle("  Sofia_M "), "sofia_m")
    }

    func testDisplayNameRules() {
        XCTAssertNil(OnboardingValidation.displayNameError("Sofia Marin"))
        XCTAssertNil(OnboardingValidation.displayNameError(String(repeating: "é", count: 64)))
        XCTAssertNotNil(OnboardingValidation.displayNameError("   "))
        XCTAssertNotNil(OnboardingValidation.displayNameError(String(repeating: "a", count: 65)))
        XCTAssertEqual(OnboardingValidation.normalizedDisplayName("  Sofia Marin \n"), "Sofia Marin")
    }
}

final class OnboardingViewModelTests: XCTestCase {
    @MainActor
    private final class Registrations {
        var sessions: [Session] = []
    }

    @MainActor
    private func makeViewModel(client: FakeGimClient = FakeGimClient()) -> (OnboardingViewModel, Registrations) {
        let registrations = Registrations()
        let viewModel = OnboardingViewModel(client: client) { registrations.sessions.append($0) }
        return (viewModel, registrations)
    }

    @MainActor
    func testUntouchedFieldsShowNoErrorsUntilSubmit() async {
        let (viewModel, registrations) = makeViewModel()
        XCTAssertNil(viewModel.serverUrlError)
        XCTAssertNil(viewModel.handleError)
        XCTAssertNil(viewModel.displayNameError)
        XCTAssertFalse(viewModel.canSubmit)

        await viewModel.submit()

        XCTAssertNotNil(viewModel.serverUrlError)
        XCTAssertNotNil(viewModel.handleError)
        XCTAssertNotNil(viewModel.displayNameError)
        XCTAssertTrue(registrations.sessions.isEmpty)
    }

    @MainActor
    func testTypedInvalidValueShowsInlineError() async {
        let (viewModel, _) = makeViewModel()
        viewModel.handle = "a!"
        XCTAssertNotNil(viewModel.handleError)
        viewModel.handle = "alex"
        XCTAssertNil(viewModel.handleError)
    }

    @MainActor
    func testSubmitRegistersNormalisedValues() async throws {
        let client = FakeGimClient()
        let (viewModel, registrations) = makeViewModel(client: client)
        viewModel.serverUrl = " https://gim.example.eu/ "
        viewModel.handle = " Sofia_M "
        viewModel.displayName = "  Sofia Marin "
        XCTAssertTrue(viewModel.canSubmit)

        await viewModel.submit()

        let session = try XCTUnwrap(registrations.sessions.first)
        XCTAssertEqual(session.serverUrl, "https://gim.example.eu")
        XCTAssertEqual(session.handle, "sofia_m")
        XCTAssertEqual(session.displayName, "Sofia Marin")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSubmitting)
        let state = try await client.loginState()
        XCTAssertEqual(state, .registered(session))
    }

    @MainActor
    func testSubmitFailureShowsPresentedError() async {
        let taken = UserProfile(userId: "user-sofia", handle: "sofia", displayName: "Sofia")
        let (viewModel, registrations) = makeViewModel(client: FakeGimClient(users: [taken]))
        viewModel.serverUrl = "https://gim.example.eu"
        viewModel.handle = "sofia"
        viewModel.displayName = "Sofia"

        await viewModel.submit()

        XCTAssertTrue(registrations.sessions.isEmpty)
        XCTAssertEqual(
            viewModel.errorMessage, ErrorPresenter.message(for: GimError.invalidInput("Handle is already taken")))
        XCTAssertFalse(viewModel.isSubmitting)
    }
}
