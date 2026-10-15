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

    func testDefaultServerUrlPrefersStoredThenArgumentThenBundled() {
        let stored = "https://gim.example.eu"
        let argument = "http://127.0.0.1:8080"
        let bundled = "http://localhost:8080"
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(stored: stored, argument: argument, bundled: bundled), stored)
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(stored: nil, argument: argument, bundled: bundled), argument)
        XCTAssertEqual(OnboardingValidation.defaultServerUrl(stored: nil, argument: nil, bundled: bundled), bundled)
        XCTAssertEqual(OnboardingValidation.defaultServerUrl(stored: nil, argument: nil, bundled: nil), "")
    }

    func testDefaultServerUrlSkipsEmptyAndInvalidCandidates() {
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(stored: "", argument: "  ", bundled: "http://localhost:8080"),
            "http://localhost:8080")
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(
                stored: "gim.example.eu", argument: "ftp://gim.example.eu", bundled: "https://gim.example.eu"),
            "https://gim.example.eu")
        XCTAssertEqual(OnboardingValidation.defaultServerUrl(stored: nil, argument: "https://", bundled: "$(X)"), "")
    }

    func testDefaultServerUrlIsNormalised() {
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(stored: nil, argument: " https://gim.example.eu/ ", bundled: nil),
            "https://gim.example.eu")
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
        var results: [Registration] = []
    }

    @MainActor
    private func makeViewModel(
        factory: RecordingFactory = RecordingFactory { _ in FakeGimClient() },
        serverUrl: String = "",
        client: (any GimClientAPI)? = nil
    ) -> (OnboardingViewModel, Registrations) {
        let registrations = Registrations()
        let viewModel = OnboardingViewModel(
            factory: factory, hooks: TestHooks(dataDir: makeTemporaryDirectory()), serverUrl: serverUrl,
            client: client
        ) { registrations.results.append($0) }
        return (viewModel, registrations)
    }

    @MainActor
    private func fill(_ viewModel: OnboardingViewModel, serverUrl: String, handle: String = "sofia_m") {
        viewModel.serverUrl = serverUrl
        viewModel.handle = handle
        viewModel.displayName = "Sofia Marin"
    }

    @MainActor
    func testUntouchedFieldsShowNoErrorsUntilSubmit() async {
        let factory = RecordingFactory { _ in FakeGimClient() }
        let (viewModel, registrations) = makeViewModel(factory: factory)
        XCTAssertNil(viewModel.serverUrlError)
        XCTAssertNil(viewModel.handleError)
        XCTAssertNil(viewModel.displayNameError)
        XCTAssertFalse(viewModel.canSubmit)

        await viewModel.submit()

        XCTAssertNotNil(viewModel.serverUrlError)
        XCTAssertNotNil(viewModel.handleError)
        XCTAssertNotNil(viewModel.displayNameError)
        XCTAssertTrue(registrations.results.isEmpty)
        XCTAssertTrue(factory.configs.isEmpty, "no client is created for invalid input")
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
    func testSubmitCreatesTheClientForTheTypedUrlAndRegisters() async throws {
        let client = FakeGimClient()
        let factory = RecordingFactory { _ in client }
        let (viewModel, registrations) = makeViewModel(factory: factory)
        viewModel.serverUrl = " https://gim.example.eu/ "
        viewModel.handle = " Sofia_M "
        viewModel.displayName = "  Sofia Marin "
        XCTAssertTrue(viewModel.canSubmit)

        await viewModel.submit()

        XCTAssertEqual(factory.configs, [ClientConfig(serverUrl: "https://gim.example.eu")])
        let result = try XCTUnwrap(registrations.results.first)
        XCTAssertTrue(result.client === client)
        XCTAssertEqual(result.config, ClientConfig(serverUrl: "https://gim.example.eu"))
        XCTAssertEqual(result.session.handle, "sofia_m")
        XCTAssertEqual(result.session.displayName, "Sofia Marin")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSubmitting)
        let session = try await client.session()
        XCTAssertEqual(session, result.session)
    }

    @MainActor
    func testFailedSubmitReusesTheClientUntilTheUrlChanges() async {
        let taken = UserProfile(userId: "user-sofia", handle: "sofia", displayName: "Sofia")
        let factory = RecordingFactory { _ in FakeGimClient(users: [taken]) }
        let (viewModel, registrations) = makeViewModel(factory: factory)
        fill(viewModel, serverUrl: "https://gim.example.eu", handle: "sofia")

        await viewModel.submit()
        await viewModel.submit()

        XCTAssertTrue(registrations.results.isEmpty)
        XCTAssertEqual(
            viewModel.errorMessage,
            ErrorPresenter.message(for: GimError.Server(status: 409, reason: "Handle is already taken")))
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertEqual(factory.configs.count, 1)

        viewModel.serverUrl = "https://other.example.eu"
        await viewModel.submit()
        XCTAssertEqual(factory.configs.map(\.serverUrl), ["https://gim.example.eu", "https://other.example.eu"])
    }

    @MainActor
    func testExistingClientIsUsedForItsUrl() async {
        let client = FakeGimClient()
        let factory = RecordingFactory { _ in FakeGimClient() }
        let (viewModel, registrations) = makeViewModel(
            factory: factory, serverUrl: "https://gim.example.eu", client: client)
        fill(viewModel, serverUrl: "https://gim.example.eu")

        await viewModel.submit()

        XCTAssertTrue(factory.configs.isEmpty)
        XCTAssertTrue(registrations.results.first?.client === client)
    }

    @MainActor
    func testClientCreationErrorIsPresented() async {
        let factory = RecordingFactory { _ in throw GimError.InvalidInput(reason: "server_url: missing host") }
        let (viewModel, registrations) = makeViewModel(factory: factory)
        fill(viewModel, serverUrl: "https://gim.example.eu")

        await viewModel.submit()

        XCTAssertTrue(registrations.results.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "server_url: missing host")
    }
}
