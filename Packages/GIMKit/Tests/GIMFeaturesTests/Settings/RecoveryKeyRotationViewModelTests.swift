import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class RecoveryKeyRotationViewModelTests: XCTestCase {
    @MainActor
    private func makeViewModel(client: any GimClientAPI) -> RecoveryKeyRotationViewModel {
        RecoveryKeyRotationViewModel(client: client, userId: "user-me", recoveryKit: FakeRecoveryKitFunctions())
    }

    @MainActor
    func testStartsIdleAndAsksForConfirmation() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = makeViewModel(client: client)
        XCTAssertEqual(viewModel.state, .idle)

        viewModel.start()

        XCTAssertEqual(viewModel.state, .confirming)
        XCTAssertNil(viewModel.kit)
    }

    @MainActor
    func testCancelGoesBackToIdleWithoutAKit() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = makeViewModel(client: client)
        viewModel.start()

        viewModel.cancel()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.kit)
    }

    @MainActor
    func testRotateShowsTheNewCodeInTheRecoveryKit() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = makeViewModel(client: client)
        viewModel.start()

        await viewModel.rotate()

        guard case .showingKit(let code) = viewModel.state else {
            return XCTFail("expected showingKit, got \(viewModel.state)")
        }
        let kit = try XCTUnwrap(viewModel.kit)
        XCTAssertEqual(kit.userId, "user-me")
        XCTAssertEqual(kit.groupedCode, RecoveryKit.groupedRecoveryCode(RecoveryKit.normalizedRecoveryCode(code)))
        XCTAssertFalse(viewModel.hasUnsyncedServers)
    }

    @MainActor
    func testConfirmingTheKitEndsTheFlow() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = makeViewModel(client: client)
        viewModel.start()
        await viewModel.rotate()
        guard case .showingKit(let code) = viewModel.state else {
            return XCTFail("expected showingKit, got \(viewModel.state)")
        }
        let kit = try XCTUnwrap(viewModel.kit)

        kit.continueToCheck()
        kit.endingInput = FakeRecoveryKitFunctions().recoveryKeyEnding(recoveryCode: code)
        kit.confirm()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.kit)
    }

    @MainActor
    func testUnsyncedServersAreReported() async throws {
        let (fake, _) = await connected(makeDemoClient())
        let viewModel = makeViewModel(client: AccountSafetyStubClient(fake, unsyncedHubIds: ["hub-b"]))
        viewModel.start()

        await viewModel.rotate()

        guard case .showingKit(let code) = viewModel.state else {
            return XCTFail("expected showingKit, got \(viewModel.state)")
        }
        XCTAssertTrue(viewModel.hasUnsyncedServers)
        let kit = try XCTUnwrap(viewModel.kit)
        kit.continueToCheck()
        kit.endingInput = FakeRecoveryKitFunctions().recoveryKeyEnding(recoveryCode: code)
        kit.confirm()
        XCTAssertTrue(viewModel.hasUnsyncedServers, "the notice stays after the kit is saved")

        viewModel.start()

        XCTAssertFalse(viewModel.hasUnsyncedServers, "a new attempt clears the notice")
    }

    @MainActor
    func testFailedRotationShowsTheError() async {
        let viewModel = makeViewModel(client: FakeGimClient())
        viewModel.start()

        await viewModel.rotate()

        guard case .failed(let message) = viewModel.state else {
            return XCTFail("expected failed, got \(viewModel.state)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertNil(viewModel.kit)

        viewModel.start()

        XCTAssertEqual(viewModel.state, .confirming, "the user can try again")
    }
}
