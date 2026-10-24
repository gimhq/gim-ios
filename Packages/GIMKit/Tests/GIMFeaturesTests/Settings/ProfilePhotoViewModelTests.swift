import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class ProfilePhotoViewModelTests: XCTestCase {
    @MainActor
    private final class Changes {
        var count = 0
    }

    @MainActor
    private func makeViewModel(client: any GimClientAPI) -> (ProfilePhotoViewModel, Changes, URL) {
        let changes = Changes()
        let cache = URL(fileURLWithPath: makeTemporaryDirectory()).appendingPathComponent("profile-photo")
        let viewModel = ProfilePhotoViewModel(client: client, cacheDirectory: cache) { changes.count += 1 }
        return (viewModel, changes, cache)
    }

    private func writePickedPhoto() throws -> String {
        let url = URL(fileURLWithPath: makeTemporaryDirectory()).appendingPathComponent("Photo.jpg")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
        return url.path
    }

    private func cachedFiles(_ cache: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
    }

    @MainActor
    func testLoadWithoutAPhotoFallsBackToInitials() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, _, _) = makeViewModel(client: client)

        await viewModel.load()

        XCTAssertFalse(viewModel.hasPhoto)
        XCTAssertNil(viewModel.photoPath)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testLoadFetchesTheOwnPhotoIntoTheCacheDirectory() async throws {
        let (client, _) = await connected(makeDemoClient())
        let picked = try writePickedPhoto()
        try await client.setAvatar(filePath: picked, mime: "image/jpeg")
        let (viewModel, _, cache) = makeViewModel(client: client)

        await viewModel.load()

        XCTAssertTrue(viewModel.hasPhoto)
        let path = try XCTUnwrap(viewModel.photoPath)
        XCTAssertTrue(path.hasPrefix(cache.path + "/"))
        XCTAssertEqual(FileManager.default.contents(atPath: path), FileManager.default.contents(atPath: picked))
    }

    @MainActor
    func testReloadReplacesTheCachedFile() async throws {
        let (client, _) = await connected(makeDemoClient())
        try await client.setAvatar(filePath: try writePickedPhoto(), mime: "image/jpeg")
        let (viewModel, _, cache) = makeViewModel(client: client)
        await viewModel.load()
        let first = try XCTUnwrap(viewModel.photoPath)

        await viewModel.load()

        let second = try XCTUnwrap(viewModel.photoPath)
        XCTAssertNotEqual(first, second, "a new path, so image caches keyed by path show the new photo")
        XCTAssertEqual(cachedFiles(cache), [URL(fileURLWithPath: second).lastPathComponent])
    }

    @MainActor
    func testSetPhotoUploadsAJPEGShowsItAndNotifies() async throws {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, changes, _) = makeViewModel(client: client)
        await viewModel.load()

        let saved = await viewModel.setPhoto(filePath: try writePickedPhoto())

        XCTAssertTrue(saved)
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.hasPhoto)
        XCTAssertNotNil(viewModel.photoPath)
        XCTAssertEqual(changes.count, 1)
        let profile = try await client.ownProfile()
        XCTAssertEqual(profile?.hasAvatar, true)
    }

    @MainActor
    func testRemovePhotoFallsBackToInitialsAndClearsTheCache() async throws {
        let (client, _) = await connected(makeDemoClient())
        try await client.setAvatar(filePath: try writePickedPhoto(), mime: "image/jpeg")
        let (viewModel, changes, cache) = makeViewModel(client: client)
        await viewModel.load()

        let removed = await viewModel.removePhoto()

        XCTAssertTrue(removed)
        XCTAssertFalse(viewModel.hasPhoto)
        XCTAssertNil(viewModel.photoPath)
        XCTAssertEqual(cachedFiles(cache), [])
        XCTAssertEqual(changes.count, 1)
        let profile = try await client.ownProfile()
        XCTAssertEqual(profile?.hasAvatar, false)
    }

    @MainActor
    func testSetPhotoWithoutASessionShowsTheError() async throws {
        let (viewModel, changes, _) = makeViewModel(client: FakeGimClient())

        let saved = await viewModel.setPhoto(filePath: try writePickedPhoto())

        XCTAssertFalse(saved)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertEqual(changes.count, 0)
    }

    @MainActor
    func testPhotoFailedShowsThePreparationError() async {
        let (client, _) = await connected(makeDemoClient())
        let (viewModel, _, _) = makeViewModel(client: client)

        viewModel.photoFailed(MediaPreparationError.unreadable)

        XCTAssertEqual(viewModel.errorMessage, MediaPreparationError.unreadable.message)
    }
}
