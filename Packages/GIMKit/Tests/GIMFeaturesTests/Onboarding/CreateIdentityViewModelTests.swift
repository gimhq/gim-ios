import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class CreateIdentityViewModelTests: XCTestCase {
    @MainActor
    private final class Created {
        var results: [(client: any GimClientAPI, recoveryCode: String?)] = []
    }

    @MainActor
    private func makeViewModel(
        client: @escaping @MainActor () async throws -> any GimClientAPI
    ) -> (CreateIdentityViewModel, Created) {
        let created = Created()
        let context = OnboardingContext(
            config: ClientConfig(serverUrl: "https://gim.example.eu"), client: client, discardClient: {},
            onRegistered: { _ in })
        let viewModel = CreateIdentityViewModel(context: context) { created.results.append(($0, $1)) }
        return (viewModel, created)
    }

    @MainActor
    func testEmptyNameShowsTheErrorOnSubmitWithoutCreatingAClient() async {
        var clientRequests = 0
        let (viewModel, created) = makeViewModel {
            clientRequests += 1
            return FakeGimClient()
        }
        XCTAssertNil(viewModel.displayNameError)
        XCTAssertFalse(viewModel.canSubmit)

        await viewModel.submit()

        XCTAssertNotNil(viewModel.displayNameError)
        XCTAssertEqual(clientRequests, 0)
        XCTAssertTrue(created.results.isEmpty)
    }

    @MainActor
    func testTooLongNameShowsInlineError() async {
        let (viewModel, _) = makeViewModel { FakeGimClient() }
        viewModel.displayName = String(repeating: "a", count: 65)
        XCTAssertNotNil(viewModel.displayNameError)
        viewModel.displayName = "Sofia"
        XCTAssertNil(viewModel.displayNameError)
    }

    @MainActor
    func testSubmitCreatesTheIdentityWithTheTrimmedNameAndReturnsTheCode() async throws {
        let client = FakeGimClient()
        let (viewModel, created) = makeViewModel { client }
        viewModel.displayName = "  Sofia Marin \n"

        await viewModel.submit()

        let result = try XCTUnwrap(created.results.first)
        XCTAssertTrue(result.client === client)
        let code = try XCTUnwrap(result.recoveryCode)
        XCTAssertEqual(code.count, 39 + 9, "39 symbols in ten groups")
        let session = try await client.session()
        XCTAssertEqual(session?.displayName, "Sofia Marin")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    @MainActor
    func testCreateIdentityErrorIsPresentedAndRetryCreatesTheIdentityOnTheSameClient() async throws {
        let client = IdentityStubClient(createIdentityErrors: [.Network(reason: "offline")])
        var clientRequests = 0
        let (viewModel, created) = makeViewModel {
            clientRequests += 1
            return client
        }
        viewModel.displayName = "Sofia"

        await viewModel.submit()

        XCTAssertTrue(created.results.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.Network(reason: "offline")))
        XCTAssertFalse(viewModel.isSubmitting)

        await viewModel.submit()

        XCTAssertEqual(created.results.count, 1, "only the code of the call that succeeded is shown")
        let result = try XCTUnwrap(created.results.first)
        XCTAssertTrue(result.client === client)
        XCTAssertNotNil(result.recoveryCode)
        let session = try await client.session()
        XCTAssertEqual(session?.displayName, "Sofia")
        XCTAssertEqual(clientRequests, 2, "the cached client is reused through the context")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testClientCreationErrorIsPresented() async {
        let (viewModel, created) = makeViewModel { throw GimError.InvalidInput(reason: "server_url: missing host") }
        viewModel.displayName = "Sofia"

        await viewModel.submit()

        XCTAssertTrue(created.results.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "server_url: missing host")
    }

    @MainActor
    func testClientWithAnIdentityShowsTheCoreError() async throws {
        let session = Session(userId: "user-sofia", deviceId: "device-1", handle: "", displayName: "Sofia")
        let client = FakeGimClient(session: session)
        let (viewModel, created) = makeViewModel { client }
        viewModel.displayName = "Someone Else"

        await viewModel.submit()

        XCTAssertTrue(created.results.isEmpty)
        XCTAssertEqual(
            viewModel.errorMessage,
            ErrorPresenter.message(for: GimError.InvalidInput(reason: "This device already has an identity")))
        let current = try await client.session()
        XCTAssertEqual(current, session)
    }

    @MainActor
    func testAHubThatDoesNotAdmitTheUserRefusesTheRegistration() async throws {
        let client = FakeGimClient()
        await client.simulateNotAdmitted(hubId: "")
        let (viewModel, created) = makeViewModel { client }
        viewModel.displayName = "Sofia"

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, "This hub does not admit your account.")
        XCTAssertTrue(created.results.isEmpty)
        let session = try await client.session()
        XCTAssertNil(session, "nothing is kept")
        XCTAssertFalse(viewModel.isSubmitting)
    }
}
