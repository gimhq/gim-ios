import Foundation
import Observation

/// Shows the recovery kit once and makes the user type the last symbols of the recovery code before continuing. The
/// code lives only in memory and is dropped as soon as the check succeeds.
@MainActor
@Observable
public final class RecoveryKitViewModel {
    /// Why the typed ending was not accepted; `text` gives the localized message.
    public enum EndingErrorKind: Sendable, Hashable {
        /// The typed symbols are not the code's ending.
        case mismatch

        /// The localized message.
        public var text: String {
            switch self {
            case .mismatch: onboardingText("That doesn't match. Look at your recovery key and try again.")
            }
        }
    }

    public static let mismatchMessage = EndingErrorKind.mismatch.text

    public let userId: String
    /// The code as returned by `createIdentity`; `nil` once confirmed.
    public private(set) var code: String?
    public let labels: RecoveryKit.Labels
    /// Whether the check step is showing instead of the kit.
    public private(set) var isChecking = false
    public var endingInput = ""
    /// Message after a wrong ending was typed.
    public var endingError: String? { endingErrorKind?.text }
    /// The kind behind `endingError`.
    public private(set) var endingErrorKind: EndingErrorKind?

    private let onConfirmed: @MainActor () -> Void

    public init(
        userId: String, code: String, labels: RecoveryKit.Labels = .localized,
        onConfirmed: @escaping @MainActor () -> Void
    ) {
        self.userId = userId
        self.code = code
        self.labels = labels
        self.onConfirmed = onConfirmed
    }

    /// The code in groups of four; empty once confirmed.
    public var groupedCode: String {
        code.map { RecoveryKit.groupedRecoveryCode(RecoveryKit.normalizedRecoveryCode($0)) } ?? ""
    }

    /// The kit text to copy, share or save; empty once confirmed.
    public var kitText: String {
        code.map { RecoveryKit.format(userId: userId, recoveryCode: $0, labels: labels) } ?? ""
    }

    /// The number of symbols the check asks for.
    public var endingLength: Int { RecoveryKit.endingSymbols }

    public var isConfirmed: Bool { code == nil }

    /// Moves from the kit to the check step.
    public func continueToCheck() {
        guard !isConfirmed else { return }
        endingInput = ""
        endingErrorKind = nil
        isChecking = true
    }

    /// Goes back to the kit; only possible before the check succeeded.
    public func showKitAgain() {
        guard !isConfirmed else { return }
        isChecking = false
    }

    /// Compares the typed ending with the code's last symbols, ignoring case, `-` and whitespace.
    public func confirm() {
        guard isChecking, let code else { return }
        guard RecoveryKit.matchesEnding(code, typed: endingInput) else {
            endingErrorKind = .mismatch
            return
        }
        self.code = nil
        endingInput = ""
        endingErrorKind = nil
        onConfirmed()
    }
}

extension RecoveryKit.Labels {
    /// The kit words in the user's language.
    public static var localized: Self {
        Self(
            title: onboardingText("gim recovery kit"),
            accountId: onboardingText("Account ID"),
            recoveryKey: onboardingText("Recovery key"),
            note: onboardingText(
                "Keep this secret. Anyone who has it can get into your account. Lost all your devices? Open gim, tap "
                    + "Restore and paste this text."))
    }
}
