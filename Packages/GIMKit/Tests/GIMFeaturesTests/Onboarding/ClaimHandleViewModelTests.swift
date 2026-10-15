import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class ClaimHandleViewModelTests: XCTestCase {
    @MainActor
    private final class Finishes {
        var count = 0
        /// Thrown by the next finish, then cleared.
        var nextError: GimError?
    }

    private let session = Session(userId: "user-sofia", deviceId: "device-1", handle: "", displayName: "Sofia")

    @MainActor
    private func makeViewModel(client: any GimClientAPI) -> (ClaimHandleViewModel, Finishes) {
        let finishes = Finishes()
        let viewModel = ClaimHandleViewModel(client: client) {
            if let error = finishes.nextError {
                finishes.nextError = nil
                throw error
            }
            finishes.count += 1
        }
        return (viewModel, finishes)
    }

    @MainActor
    func testInvalidHandleIsRejectedLocally() async {
        let client = FakeGimClient(session: session)
        let (viewModel, finishes) = makeViewModel(client: client)
        XCTAssertNil(viewModel.handleError)
        XCTAssertFalse(viewModel.canClaim)

        await viewModel.claim()
        XCTAssertNotNil(viewModel.handleError, "empty")

        viewModel.handle = "so"
        XCTAssertNotNil(viewModel.handleError)
        viewModel.handle = "so fia"
        await viewModel.claim()

        XCTAssertEqual(finishes.count, 0)
        let current = try? await client.session()
        XCTAssertEqual(current?.handle, "")
    }

    @MainActor
    func testClaimNormalisesTheHandleAndFinishes() async throws {
        let client = FakeGimClient(session: session)
        let (viewModel, finishes) = makeViewModel(client: client)
        viewModel.handle = " Sofia_M "

        await viewModel.claim()

        XCTAssertEqual(finishes.count, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSubmitting)
        let current = try await client.session()
        XCTAssertEqual(current?.handle, "sofia_m")
    }

    @MainActor
    func testTakenHandleShowsTakenMessage() async {
        let taken = UserProfile(userId: "user-other", handle: "sofia", displayName: "Other")
        let (viewModel, finishes) = makeViewModel(client: FakeGimClient(users: [taken], session: session))
        viewModel.handle = "sofia"

        await viewModel.claim()

        XCTAssertEqual(viewModel.errorMessage, "This handle is taken.")
        XCTAssertEqual(finishes.count, 0)

        viewModel.handle = "sofia_m"
        await viewModel.claim()
        XCTAssertEqual(finishes.count, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testOtherClaimErrorsArePresented() async {
        let client = IdentityStubClient(
            FakeGimClient(session: session), claimHandleError: .RetryLater(status: 429, retryAfterSecs: 5, reason: ""))
        let (viewModel, finishes) = makeViewModel(client: client)
        viewModel.handle = "sofia"

        await viewModel.claim()

        XCTAssertEqual(
            viewModel.errorMessage,
            ErrorPresenter.message(for: GimError.RetryLater(status: 429, retryAfterSecs: 5, reason: "")))
        XCTAssertEqual(finishes.count, 0)
    }

    @MainActor
    func testSkipFinishesWithoutClaiming() async throws {
        let client = FakeGimClient(session: session)
        let (viewModel, finishes) = makeViewModel(client: client)
        viewModel.handle = "ignored"

        await viewModel.skip()

        XCTAssertEqual(finishes.count, 1)
        let current = try await client.session()
        XCTAssertEqual(current?.handle, "")
    }

    @MainActor
    func testFinishErrorIsPresentedAndRetryable() async {
        let (viewModel, finishes) = makeViewModel(client: FakeGimClient(session: session))
        finishes.nextError = .NotRegistered

        await viewModel.skip()

        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.NotRegistered))
        XCTAssertEqual(finishes.count, 0)

        await viewModel.skip()
        XCTAssertEqual(finishes.count, 1)
        XCTAssertNil(viewModel.errorMessage)
    }
}
