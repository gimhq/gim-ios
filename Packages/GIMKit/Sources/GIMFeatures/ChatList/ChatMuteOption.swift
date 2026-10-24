import Foundation
import GIMClientKit

/// How long `ChatListViewModel.mute` silences a chat's notifications.
public enum ChatMuteOption: Sendable, Hashable, CaseIterable {
    case oneHour
    case eightHours
    case oneWeek
    /// Until the user unmutes the chat.
    case always

    /// `ChatSummary.mutedUntilMs` for a mute starting at `now`.
    public func mutedUntilMs(now: Date) -> UInt64 {
        let hourMs: UInt64 = 3_600_000
        switch self {
        case .oneHour: return now.epochMilliseconds + hourMs
        case .eightHours: return now.epochMilliseconds + 8 * hourMs
        case .oneWeek: return now.epochMilliseconds + 7 * 24 * hourMs
        case .always: return mutedForever()
        }
    }

    /// The menu item, localized through the FeaturesChat table.
    public var title: String {
        switch self {
        case .oneHour:
            NSLocalizedString(
                "For 1 hour", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle, value: "For 1 hour",
                comment: "")
        case .eightHours:
            NSLocalizedString(
                "For 8 hours", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle, value: "For 8 hours",
                comment: "")
        case .oneWeek:
            NSLocalizedString(
                "For 1 week", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle, value: "For 1 week",
                comment: "")
        case .always:
            NSLocalizedString(
                "Always", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle, value: "Always", comment: "")
        }
    }
}
