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
    }

    func testDefaultServerUrlFallsBackToTheBuiltInHub() {
        XCTAssertEqual(OnboardingValidation.builtInServerUrl, "https://hub.g.im")
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(stored: nil, argument: nil, bundled: nil), "https://hub.g.im")
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(stored: "", argument: "  ", bundled: ""), "https://hub.g.im")
    }

    func testEachConfiguredDefaultWinsOverTheBuiltInHub() {
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(stored: nil, argument: nil, bundled: "http://localhost:8080"),
            "http://localhost:8080")
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(stored: nil, argument: "http://127.0.0.1:8080", bundled: nil),
            "http://127.0.0.1:8080")
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(stored: "https://gim.example.eu", argument: nil, bundled: nil),
            "https://gim.example.eu")
    }

    func testDefaultServerUrlSkipsEmptyAndInvalidCandidates() {
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(stored: "", argument: "  ", bundled: "http://localhost:8080"),
            "http://localhost:8080")
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(
                stored: "gim.example.eu", argument: "ftp://gim.example.eu", bundled: "https://gim.example.eu"),
            "https://gim.example.eu")
        XCTAssertEqual(
            OnboardingValidation.defaultServerUrl(stored: nil, argument: "https://", bundled: "$(X)"),
            "https://hub.g.im")
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
    final class Registrations {
        var results: [Registration] = []
    }

    @MainActor
    private func makeViewModel(
        factory: RecordingFactory = RecordingFactory { _ in FakeGimClient() },
        serverUrl: String = "",
        client: (any GimClientAPI)? = nil,
        localStateReset: Bool = false,
        recoveryKit: any RecoveryKitFunctions = FakeRecoveryKitFunctions()
    ) -> (OnboardingViewModel, Registrations) {
        let registrations = Registrations()
        let viewModel = OnboardingViewModel(
            factory: factory, hooks: TestHooks(dataDir: makeTemporaryDirectory()),
            recoveryKit: recoveryKit, serverUrl: serverUrl, client: client,
            localStateReset: localStateReset
        ) { registrations.results.append($0) }
        return (viewModel, registrations)
    }

    @MainActor
    func testChoosingWithAnInvalidServerShowsTheErrorAndStays() async {
        let factory = RecordingFactory { _ in FakeGimClient() }
        let (viewModel, _) = makeViewModel(factory: factory)
        XCTAssertNil(viewModel.serverUrlError, "untouched field")

        viewModel.choose(.createIdentity)

        XCTAssertNotNil(viewModel.serverUrlError)
        XCTAssertTrue(viewModel.path.isEmpty)
        XCTAssertNil(viewModel.context)
        XCTAssertNil(viewModel.createIdentity)
        XCTAssertTrue(factory.configs.isEmpty)
    }

    @MainActor
    func testTheServerFieldIsHiddenWithAValidDefaultServer() async {
        let (viewModel, _) = makeViewModel(serverUrl: "https://gim.example.eu")
        XCTAssertFalse(viewModel.showsServerField)

        viewModel.choose(.createIdentity)

        XCTAssertFalse(viewModel.showsServerField)
        XCTAssertEqual(viewModel.path, [.createIdentity])
    }

    @MainActor
    func testTheServerFieldIsShownWithoutADefaultServer() async {
        let (viewModel, _) = makeViewModel(serverUrl: "")
        XCTAssertTrue(viewModel.showsServerField)
    }

    @MainActor
    func testRevealingTheServerFieldShowsIt() async {
        let (viewModel, _) = makeViewModel(serverUrl: "https://gim.example.eu")

        viewModel.revealServerField()

        XCTAssertTrue(viewModel.showsServerField)
    }

    @MainActor
    func testChoosingWithAnInvalidTypedServerRevealsTheFieldAndStays() async {
        let (viewModel, _) = makeViewModel(serverUrl: "https://gim.example.eu")
        viewModel.serverUrl = "gim.example.eu"

        viewModel.choose(.restore)

        XCTAssertTrue(viewModel.showsServerField)
        XCTAssertNotNil(viewModel.serverUrlError)
        XCTAssertTrue(viewModel.path.isEmpty)
        XCTAssertNil(viewModel.context)
    }

    @MainActor
    func testTypedInvalidServerShowsInlineError() async {
        let (viewModel, _) = makeViewModel()
        viewModel.serverUrl = "gim.example.eu"
        XCTAssertNotNil(viewModel.serverUrlError)
        viewModel.serverUrl = "https://gim.example.eu"
        XCTAssertNil(viewModel.serverUrlError)
    }

    @MainActor
    func testChoosingOpensTheRouteForTheNormalisedServer() async {
        let (viewModel, _) = makeViewModel(serverUrl: " https://gim.example.eu/ ")
        for route in [OnboardingRoute.linkDevice, .restore, .createIdentity] {
            viewModel.choose(route)
            XCTAssertEqual(viewModel.path, [route])
            XCTAssertEqual(viewModel.context?.config, ClientConfig(serverUrl: "https://gim.example.eu"))
            XCTAssertEqual(viewModel.createIdentity != nil, route == .createIdentity)
        }
    }

    @MainActor
    func testLocalStateResetNoticeIsShownUntilDismissed() async {
        let (viewModel, _) = makeViewModel(localStateReset: true)
        XCTAssertTrue(viewModel.showsLocalStateResetNotice)
        viewModel.dismissLocalStateResetNotice()
        XCTAssertFalse(viewModel.showsLocalStateResetNotice)

        let (fresh, _) = makeViewModel()
        XCTAssertFalse(fresh.showsLocalStateResetNotice)
    }

    @MainActor
    func testTheInjectedRecoveryKitFunctionsReachTheContextAndTheKit() async throws {
        let recording = RecordingRecoveryKitFunctions()
        let (viewModel, _) = makeViewModel(serverUrl: "https://gim.example.eu", recoveryKit: recording)
        viewModel.choose(.createIdentity)
        XCTAssertTrue(try XCTUnwrap(viewModel.context).recoveryKit as? RecordingRecoveryKitFunctions === recording)
        let create = try XCTUnwrap(viewModel.createIdentity)
        create.displayName = "Sofia"
        await create.submit()
        guard case .recoveryKit(let recovery) = viewModel.stage else { return XCTFail("expected the recovery kit") }

        _ = recovery.kitText

        XCTAssertEqual(
            recording.calls,
            [.format(userId: recovery.userId, recoveryCode: try XCTUnwrap(recovery.code), labels: .localized)])
    }

    @MainActor
    func testCreateFlowShowsTheKitChecksTheEndingClaimsTheHandleAndRegisters() async throws {
        let client = FakeGimClient()
        let factory = RecordingFactory { _ in client }
        let (viewModel, registrations) = makeViewModel(factory: factory, serverUrl: "https://gim.example.eu/")
        viewModel.choose(.createIdentity)
        let create = try XCTUnwrap(viewModel.createIdentity)
        create.displayName = "  Sofia Marin "

        await create.submit()

        XCTAssertEqual(factory.configs, [ClientConfig(serverUrl: "https://gim.example.eu")])
        guard case .recoveryKit(let recovery) = viewModel.stage else {
            return XCTFail("expected the recovery kit, got \(String(describing: viewModel.stage))")
        }
        XCTAssertEqual(recovery.userId, client.userId())
        XCTAssertEqual(recovery.groupedCode.split(separator: "-").count, 10)
        recovery.continueToCheck()
        // The last four symbols, typed in lowercase with a dash.
        let ending = FakeRecoveryKitFunctions().recoveryKeyEnding(recoveryCode: recovery.groupedCode).lowercased()
        recovery.endingInput = "\(ending.prefix(1))-\(ending.dropFirst())"
        recovery.confirm()

        XCTAssertNil(recovery.code, "the code is dropped after confirmation")
        guard case .claimHandle(let claim) = viewModel.stage else {
            return XCTFail("expected the handle step, got \(String(describing: viewModel.stage))")
        }
        claim.handle = " Sofia_M "
        await claim.claim()

        let result = try XCTUnwrap(registrations.results.first)
        XCTAssertTrue(result.client === client)
        XCTAssertEqual(result.config, ClientConfig(serverUrl: "https://gim.example.eu"))
        XCTAssertEqual(result.session.handle, "sofia_m")
        XCTAssertEqual(result.session.displayName, "Sofia Marin")
        let session = try await client.session()
        XCTAssertEqual(session, result.session)
    }

    @MainActor
    func testSkippingTheHandleRegistersWithoutOne() async throws {
        let (viewModel, registrations) = makeViewModel(serverUrl: "https://gim.example.eu")
        viewModel.choose(.createIdentity)
        let create = try XCTUnwrap(viewModel.createIdentity)
        create.displayName = "Sofia"
        await create.submit()
        guard case .recoveryKit(let recovery) = viewModel.stage else { return XCTFail("expected the recovery kit") }
        recovery.continueToCheck()
        recovery.endingInput = FakeRecoveryKitFunctions().recoveryKeyEnding(recoveryCode: recovery.groupedCode)
        recovery.confirm()
        guard case .claimHandle(let claim) = viewModel.stage else { return XCTFail("expected the handle step") }

        await claim.skip()

        XCTAssertEqual(registrations.results.first?.session.handle, "")
    }

    @MainActor
    func testClientWithAnIdentityShowsTheCoreErrorInsteadOfSkippingTheCode() async throws {
        let session = Session(userId: "user-sofia", deviceId: "device-1", handle: "", displayName: "Sofia")
        let client = FakeGimClient(session: session)
        let factory = RecordingFactory { _ in FakeGimClient() }
        let (viewModel, _) = makeViewModel(factory: factory, serverUrl: "https://gim.example.eu", client: client)
        viewModel.choose(.createIdentity)
        let create = try XCTUnwrap(viewModel.createIdentity)
        create.displayName = "Sofia"

        await create.submit()

        XCTAssertTrue(factory.configs.isEmpty, "the existing client is used for its URL")
        XCTAssertNil(viewModel.stage)
        XCTAssertEqual(
            create.errorMessage,
            ErrorPresenter.message(for: GimError.InvalidInput(reason: "This device already has an identity")))
    }

    @MainActor
    func testContextReusesTheClientUntilDiscardedOrTheUrlChanges() async throws {
        let factory = RecordingFactory { _ in FakeGimClient() }
        let (viewModel, _) = makeViewModel(factory: factory, serverUrl: "https://gim.example.eu")
        viewModel.choose(.linkDevice)
        let context = try XCTUnwrap(viewModel.context)
        let first = try await context.client()
        let again = try await context.client()
        XCTAssertTrue(first === again)

        context.discardClient()
        let afterDiscard = try await context.client()
        XCTAssertFalse(first === afterDiscard)

        viewModel.path = []
        viewModel.serverUrl = "https://other.example.eu"
        viewModel.choose(.restore)
        _ = try await XCTUnwrap(viewModel.context).client()
        XCTAssertEqual(
            factory.configs.map(\.serverUrl),
            ["https://gim.example.eu", "https://gim.example.eu", "https://other.example.eu"])
    }

    @MainActor
    func testContextCompletionRegisters() async throws {
        let (viewModel, registrations) = makeViewModel(serverUrl: "https://gim.example.eu")
        viewModel.choose(.restore)
        let context = try XCTUnwrap(viewModel.context)
        let session = Session(userId: "user-sofia", deviceId: "device-2", handle: "sofia", displayName: "Sofia")

        context.onRegistered(Registration(client: FakeGimClient(), config: context.config, session: session))

        XCTAssertEqual(registrations.results.map(\.session), [session])
    }
}
