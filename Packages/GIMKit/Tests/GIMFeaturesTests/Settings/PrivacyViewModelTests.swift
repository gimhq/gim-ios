import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class PrivacyViewModelTests: XCTestCase {
    @MainActor
    func testLoadReadsTheSettings() async throws {
        let (client, _) = await connected(makeDemoClient())
        try await client.setTypingIndicators(enabled: false)
        try await client.blockUser(userId: "user-sofia")
        let viewModel = PrivacyViewModel(client: client)

        await viewModel.load()

        XCTAssertTrue(viewModel.readReceipts)
        XCTAssertFalse(viewModel.typingIndicators)
        XCTAssertEqual(viewModel.blockedCount, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testSetReadReceiptsStoresTheValue() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = PrivacyViewModel(client: client)
        await viewModel.load()

        await viewModel.setReadReceipts(false)

        XCTAssertFalse(viewModel.readReceipts)
        XCTAssertNil(viewModel.errorMessage)
        let stored = try await client.privacy()
        XCTAssertFalse(stored.readReceipts)
        XCTAssertTrue(stored.typingIndicators)
    }

    @MainActor
    func testSetTypingIndicatorsStoresTheValue() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = PrivacyViewModel(client: client)
        await viewModel.load()

        await viewModel.setTypingIndicators(false)

        XCTAssertFalse(viewModel.typingIndicators)
        XCTAssertNil(viewModel.errorMessage)
        let stored = try await client.privacy()
        XCTAssertFalse(stored.typingIndicators)
        XCTAssertTrue(stored.readReceipts)
    }

    @MainActor
    func testFailedChangesRevertTheToggleAndShowTheError() async {
        let viewModel = PrivacyViewModel(client: FakeGimClient())
        await viewModel.load()

        await viewModel.setReadReceipts(false)

        XCTAssertTrue(viewModel.readReceipts)
        XCTAssertNotNil(viewModel.errorMessage)

        await viewModel.setTypingIndicators(false)

        XCTAssertTrue(viewModel.typingIndicators)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    @MainActor
    func testASuccessfulChangeClearsTheError() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = PrivacyViewModel(client: client)
        await viewModel.load()
        await client.simulateSuspension(hubId: "")
        await viewModel.setReadReceipts(false)
        XCTAssertNotNil(viewModel.errorMessage)

        await client.simulateSuspension(hubId: nil)
        await viewModel.setReadReceipts(false)

        XCTAssertFalse(viewModel.readReceipts)
        XCTAssertNil(viewModel.errorMessage)
    }
}
