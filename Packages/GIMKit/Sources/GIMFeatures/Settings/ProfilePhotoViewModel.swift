import Foundation
import GIMClientKit
import Observation

/// The own profile photo: shows it from a cache file and sets or removes it.
@MainActor
@Observable
public final class ProfilePhotoViewModel {
    /// Side of the square JPEG a picked photo is cropped and scaled to: every member of every chat downloads it, and
    /// gim-core documents no limit of its own.
    public static let maxPixelSize = 512
    public static let mime = "image/jpeg"

    public private(set) var hasPhoto = false
    /// The cached photo; `nil` without a photo or while it cannot be downloaded: show the initials.
    public private(set) var photoPath: String?
    public private(set) var isSaving = false
    /// Error from the last failed load, change or photo preparation, already localized.
    public private(set) var errorMessage: String?

    private let client: any GimClientAPI
    private let cacheDirectory: URL
    private let onChanged: @MainActor () async -> Void

    /// - Parameters:
    ///   - cacheDirectory: a directory owned by this view model (under the app's caches directory); its files are
    ///     replaced on every load.
    ///   - onChanged: runs after every successful change so the app can re-read its session.
    public init(client: any GimClientAPI, cacheDirectory: URL, onChanged: @escaping @MainActor () async -> Void) {
        self.client = client
        self.cacheDirectory = cacheDirectory
        self.onChanged = onChanged
    }

    public func load() async {
        do {
            try await refresh()
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
        }
    }

    /// Sets the photo from a JPEG prepared to `maxPixelSize`; `false` when it was not set.
    @discardableResult
    public func setPhoto(filePath: String) async -> Bool {
        await change { try await client.setAvatar(filePath: filePath, mime: Self.mime) }
    }

    /// Removes the photo; `false` when it was not removed.
    @discardableResult
    public func removePhoto() async -> Bool {
        await change { try await client.removeAvatar() }
    }

    /// The picked photo could not be prepared.
    public func photoFailed(_ error: any Error) {
        errorMessage = ((error as? MediaPreparationError) ?? .unreadable).message
    }

    /// Re-reads the own profile and downloads the photo to a new file, so image caches keyed by path show it.
    private func refresh() async throws {
        let profile = try await client.ownProfile()
        hasPhoto = profile?.hasAvatar ?? false
        var path: String?
        if let profile, profile.hasAvatar {
            let destination = cacheDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            path = try? await client.fetchUserAvatar(userId: profile.userId, destPath: destination.path)
        }
        photoPath = path
        removeCachedFiles(except: path)
    }

    private func removeCachedFiles(except kept: String?) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
        for name in names {
            let url = cacheDirectory.appendingPathComponent(name)
            if url.path != kept { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func change(_ operation: () async throws -> Void) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await operation()
            try await refresh()
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
            return false
        }
        await onChanged()
        return true
    }
}
