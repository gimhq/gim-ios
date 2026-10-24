import Foundation
import GIMClientKit
import Observation

/// The privacy screen: read receipts, typing indicators and the number of blocked people.
@MainActor
@Observable
public final class PrivacyViewModel {
    /// Off: no read receipts are sent and the others' are not shown either.
    public private(set) var readReceipts = true
    /// Off: no typing indicators are sent and the others' are not shown either.
    public private(set) var typingIndicators = true
    public private(set) var blockedCount = 0
    /// Error from the last failed load or change, already localized by `ErrorPresenter`.
    public private(set) var errorMessage: String?

    private let client: any GimClientAPI

    public init(client: any GimClientAPI) {
        self.client = client
    }

    public func load() async {
        do {
            let settings = try await client.privacy()
            readReceipts = settings.readReceipts
            typingIndicators = settings.typingIndicators
            blockedCount = settings.blockedUserIds.count
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
        }
    }

    /// Shows the new value at once and reverts it when the change fails.
    public func setReadReceipts(_ enabled: Bool) async {
        let previous = readReceipts
        readReceipts = enabled
        if await !change({ try await client.setReadReceipts(enabled: enabled) }) { readReceipts = previous }
    }

    /// Shows the new value at once and reverts it when the change fails.
    public func setTypingIndicators(_ enabled: Bool) async {
        let previous = typingIndicators
        typingIndicators = enabled
        if await !change({ try await client.setTypingIndicators(enabled: enabled) }) { typingIndicators = previous }
    }

    private func change(_ operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
            errorMessage = nil
            return true
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
            return false
        }
    }
}
