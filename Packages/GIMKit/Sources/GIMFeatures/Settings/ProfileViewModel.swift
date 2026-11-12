import Foundation
import GIMClientKit
import Observation

/// The profile screen: edits the display name.
@MainActor
@Observable
public final class ProfileViewModel {
    /// Why the name draft cannot be saved; GIMUI localizes it.
    public enum NameError: Sendable, Hashable {
        case empty
        case tooLong
    }

    public private(set) var session: Session?
    /// The display name draft, seeded from the session by `load()`.
    public var name = ""
    public private(set) var isSaving = false
    /// Error from the last failed load or save, already localized by `ErrorPresenter`.
    public private(set) var errorMessage: String?

    private let client: any GimClientAPI
    private let onChanged: @MainActor () async -> Void

    /// - Parameter onChanged: runs after every successful change so the app can re-read its session.
    public init(client: any GimClientAPI, onChanged: @escaping @MainActor () async -> Void) {
        self.client = client
        self.onChanged = onChanged
    }

    public func load() async {
        do {
            session = try await client.session()
            name = session?.displayName ?? ""
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
        }
    }

    public var nameError: NameError? {
        let normalized = OnboardingValidation.normalizedDisplayName(name)
        if normalized.isEmpty { return .empty }
        if normalized.count > OnboardingValidation.displayNameMaxLength { return .tooLong }
        return nil
    }

    public var canSave: Bool {
        nameError == nil && OnboardingValidation.normalizedDisplayName(name) != session?.displayName && !isSaving
    }

    /// Stores the normalized draft as the display name; `false` when nothing was saved.
    @discardableResult
    public func saveName() async -> Bool {
        guard canSave else { return false }
        return await change {
            try await client.setDisplayName(name: OnboardingValidation.normalizedDisplayName(name))
        }
    }

    /// Runs `operation`, re-reads the session and notifies `onChanged`; presents the error otherwise.
    private func change(_ operation: () async throws -> Void) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await operation()
            session = try await client.session()
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
            return false
        }
        await onChanged()
        return true
    }
}
