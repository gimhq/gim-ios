import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class ProfileViewModelTests: XCTestCase {
    @MainActor
    private final class Changes {
        var count = 0
    }

    @MainActor
    private func makeViewModel(client: any GimClientAPI) -> (ProfileViewModel, Changes) {
        let changes = Changes()
        let viewModel = ProfileViewModel(client: client) { changes.count += 1 }
        return (viewModel, changes)
    }

    @MainActor
    func testLoadSeedsTheDraftFromTheSession() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, changes) = makeViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.name, "Alex Morgan")
        XCTAssertEqual(viewModel.session?.handle, "alex")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.canSave)
        XCTAssertEqual(changes.count, 0)
    }

    @MainActor
    func testNameValidation() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, _) = makeViewModel(client: client)
        await viewModel.load()

        viewModel.name = ""
        XCTAssertEqual(viewModel.nameError, .empty)
        XCTAssertFalse(viewModel.canSave)

        viewModel.name = "   "
        XCTAssertEqual(viewModel.nameError, .empty)

        viewModel.name = String(repeating: "a", count: 65)
        XCTAssertEqual(viewModel.nameError, .tooLong)
        XCTAssertFalse(viewModel.canSave)

        viewModel.name = String(repeating: "a", count: 64)
        XCTAssertNil(viewModel.nameError)
        XCTAssertTrue(viewModel.canSave)
    }

    @MainActor
    func testSaveNameStoresTheNormalizedNameAndNotifies() async throws {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, changes) = makeViewModel(client: client)
        await viewModel.load()

        viewModel.name = " Alex M. "
        XCTAssertTrue(viewModel.canSave)

        let saved = await viewModel.saveName()

        XCTAssertTrue(saved)
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(changes.count, 1)
        let session = try await client.session()
        XCTAssertEqual(session?.displayName, "Alex M.")
        XCTAssertEqual(viewModel.session?.displayName, "Alex M.")
        XCTAssertFalse(viewModel.canSave, "unchanged after saving")
    }

    @MainActor
    func testSaveNameWithoutASessionFails() async {
        let (viewModel, changes) = makeViewModel(client: FakeGimClient())
        viewModel.name = "Alex"
        XCTAssertTrue(viewModel.canSave)

        let saved = await viewModel.saveName()

        XCTAssertFalse(saved)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertEqual(changes.count, 0)
    }
}
