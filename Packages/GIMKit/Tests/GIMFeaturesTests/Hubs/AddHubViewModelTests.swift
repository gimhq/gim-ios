import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class AddHubViewModelTests: XCTestCase {
    private let session = Session(userId: "user-kai", deviceId: "device-1", handle: "kai", displayName: "Kai")

    private func makeClient() -> FakeGimClient {
        FakeGimClient(scheduler: ManualFakeScheduler(), dataDirectory: makeTemporaryDirectory(), session: session)
    }

    @MainActor
    func testTheUrlFollowsTheServerUrlRule() {
        let viewModel = AddHubViewModel(client: makeClient())

        XCTAssertNil(viewModel.urlError)
        XCTAssertFalse(viewModel.canSubmit)
        viewModel.url = "hub2.example.eu"
        XCTAssertEqual(viewModel.urlError, "Enter a full address starting with http:// or https://.")
        XCTAssertFalse(viewModel.canSubmit)
        viewModel.url = "ftp://hub2.example.eu"
        XCTAssertNotNil(viewModel.urlError)
        viewModel.url = " https://hub2.example.eu/ "
        XCTAssertNil(viewModel.urlError)
        XCTAssertTrue(viewModel.canSubmit)
    }

    @MainActor
    func testSubmitAddsTheNormalizedUrl() async throws {
        let client = makeClient()
        let viewModel = AddHubViewModel(client: client)
        viewModel.url = " https://hub2.example.eu/ "

        await viewModel.submit()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertEqual(viewModel.addedHub?.url, "https://hub2.example.eu")
        XCTAssertEqual(viewModel.addedHub?.state, .unverified)
        let hubs = try await client.hubs()
        XCTAssertEqual(hubs.map(\.url), [FakeGimClient.defaultHomeHubUrl, "https://hub2.example.eu"])
    }

    @MainActor
    func testSubmitDoesNothingForAnInvalidUrl() async throws {
        let client = makeClient()
        let viewModel = AddHubViewModel(client: client)
        viewModel.url = "not a url"

        await viewModel.submit()

        XCTAssertNil(viewModel.addedHub)
        XCTAssertNil(viewModel.errorMessage)
        let count = try await client.hubs().count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testAddErrorsAreShownInline() async {
        let cases: [(url: String, error: GimError)] = [
            ("https://unverified.example.eu", .HubNotVerified(reason: "")),
            ("https://unreachable.example.eu", .Network(reason: "")),
            (
                "https://nohub.example.eu",
                .InvalidInput(reason: "url: https://nohub.example.eu does not serve a gim hub")
            ),
        ]
        for (url, error) in cases {
            let viewModel = AddHubViewModel(client: makeClient())
            viewModel.url = url

            await viewModel.submit()

            XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: error), url)
            XCTAssertNil(viewModel.addedHub, url)
            XCTAssertFalse(viewModel.isSubmitting, url)
            XCTAssertTrue(viewModel.canSubmit, url)
        }
        XCTAssertEqual(
            ErrorPresenter.message(for: GimError.HubNotVerified(reason: "")),
            "This hub couldn't prove it is reachable at this address. Check the address and try again.")
    }
}
