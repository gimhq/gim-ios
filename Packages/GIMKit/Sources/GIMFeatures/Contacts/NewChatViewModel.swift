import Foundation
import GIMClientKit
import Observation

/// Starts a direct chat with the user of a scanned or typed Account ID.
@MainActor
@Observable
public final class NewChatViewModel {
    /// Outcome of `startChat(scanned:)`.
    public enum ScanResult: Sendable, Hashable {
        case started(chatId: String)
        /// The text holds no valid Account ID.
        case noUserId
        case failed(String)
    }

    /// `createDirectChat` fails with `NotFound` when the user does not exist or has no device.
    public static let notFoundMessage = NSLocalizedString(
        "No one uses this Account ID.", tableName: "FeaturesContacts", bundle: FeaturesLocalization.bundle,
        value: "No one uses this Account ID.", comment: "")

    public private(set) var isStarting = false
    /// Error from the last failed `startChat(scanned:)`.
    public private(set) var startError: String?

    private let client: any GimClientAPI

    public init(client: any GimClientAPI) {
        self.client = client
    }

    /// Starts (or reopens) the direct chat with the first valid Account ID in scanned or typed `text`.
    public func startChat(scanned text: String) async -> ScanResult {
        guard let userId = UserID.firstValid(in: text) else { return .noUserId }
        isStarting = true
        startError = nil
        defer { isStarting = false }
        let message: String
        do {
            return .started(chatId: try await client.createDirectChat(userId: userId))
        } catch GimError.NotFound {
            message = Self.notFoundMessage
        } catch GimError.ContactNotAdmitted(let userIds) {
            message = ErrorPresenter.contactNotAdmittedMessage(userIds: userIds, profiles: [])
        } catch {
            message = await ErrorPresenter.message(for: error, client: client)
        }
        startError = message
        return .failed(message)
    }
}
