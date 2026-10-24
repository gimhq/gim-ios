import Foundation
import GIMClientKit
import Observation

/// Restores the user on this device from the recovery code with the onboarding's client. A pasted recovery kit fills
/// the user ID and recovery code fields. After success it shows that chats are not rejoined automatically; dismissing
/// that notice signs in.
@MainActor
@Observable
public final class RestoreViewModel {
    /// An error of the restore form; `text` gives the localized message.
    public enum ErrorKind: Sendable, Hashable {
        /// gim-core found no user with this user id (`NotFound`).
        case notFound
        /// The recovery code doesn't fit the user (`Crypto`).
        case wrongCode
        case userIdMissing
        case recoveryCodeMissing
        /// The kit text contains neither a user id nor a recovery code.
        case kitNotRecognized
        /// The kit text contains only one of the user id and the recovery code.
        case kitPartMissing
        /// Any other restore error, presented like on registration.
        case error(ErrorPresenter.Kind)

        /// The localized message.
        public var text: String {
            switch self {
            case .notFound:
                onboardingText("This server has no account with this Account ID. Check the ID and the server.")
            case .wrongCode:
                onboardingText("This recovery key doesn't fit this account. Check the key and the Account ID.")
            case .userIdMissing: onboardingText("Enter your Account ID.")
            case .recoveryCodeMissing: onboardingText("Enter your recovery key.")
            case .kitNotRecognized:
                onboardingText(
                    "We couldn't find an Account ID or recovery key here. Paste the whole kit, or type them below.")
            case .kitPartMissing: onboardingText("Part of the kit is missing. Fill in the empty field below.")
            case .error(let kind): ErrorPresenter.text(for: kind)
            }
        }
    }

    /// The pasted recovery kit; each part found in it replaces its field.
    public var kitText = "" {
        didSet { if kitText != oldValue { kitChanged() } }
    }
    /// What the kit text contains; `nil` while it is blank.
    public private(set) var parsed: ParsedRecoveryKit?
    /// Set by `enterSeparately()` to show the fields without a kit.
    public private(set) var showsSeparateFields = false
    public var userId = ""
    public var recoveryCode = ""
    /// Revokes every previously listed device of the user.
    public var revokeOthers = true

    public private(set) var isSubmitting = false
    /// Error from the last failed submission.
    public var errorMessage: String? { errorKind?.text }
    /// The kind behind `errorMessage`.
    public private(set) var errorKind: ErrorKind?
    /// Set by the first submit attempt so empty fields also show their messages.
    public private(set) var showsAllErrors = false
    /// Whether the restore succeeded and the notice about chats waits to be dismissed with `finish()`.
    public var showsRejoinNotice: Bool { registration != nil }

    public static let notFoundMessage = ErrorKind.notFound.text
    public static let wrongCodeMessage = ErrorKind.wrongCode.text
    public static let userIdMissingMessage = ErrorKind.userIdMissing.text
    public static let recoveryCodeMissingMessage = ErrorKind.recoveryCodeMissing.text
    public static let kitNotRecognizedMessage = ErrorKind.kitNotRecognized.text
    public static let kitPartMissingMessage = ErrorKind.kitPartMissing.text

    private let context: OnboardingContext
    private var registration: Registration?

    public init(context: OnboardingContext) {
        self.context = context
    }

    /// Whether the user ID and recovery code fields are shown: after `enterSeparately()` or once the kit text
    /// contains one of them.
    public var showsFields: Bool {
        showsSeparateFields || parsed?.userId != nil || parsed?.recoveryCode != nil
    }

    /// Message for the kit text; `nil` while it is blank or both parts were found.
    public var kitError: String? {
        kitErrorKind?.text
    }

    /// The kind behind `kitError`.
    public var kitErrorKind: ErrorKind? {
        guard let parsed else { return nil }
        switch (parsed.userId, parsed.recoveryCode) {
        case (.some, .some): return nil
        case (nil, nil): return .kitNotRecognized
        default: return .kitPartMissing
        }
    }

    public func enterSeparately() {
        showsSeparateFields = true
    }

    /// Inline message for the user id field; `nil` while the field is untouched.
    public var userIdError: String? {
        userIdErrorKind?.text
    }

    /// The kind behind `userIdError`.
    public var userIdErrorKind: ErrorKind? {
        guard showsAllErrors || !userId.isEmpty else { return nil }
        return Self.normalized(userId).isEmpty ? .userIdMissing : nil
    }

    /// Inline message for the recovery code field; `nil` while the field is untouched. gim-core validates the format.
    public var recoveryCodeError: String? {
        recoveryCodeErrorKind?.text
    }

    /// The kind behind `recoveryCodeError`.
    public var recoveryCodeErrorKind: ErrorKind? {
        guard showsAllErrors || !recoveryCode.isEmpty else { return nil }
        return Self.normalized(recoveryCode).isEmpty ? .recoveryCodeMissing : nil
    }

    public var canSubmit: Bool {
        !Self.normalized(userId).isEmpty && !Self.normalized(recoveryCode).isEmpty && !isSubmitting
            && registration == nil
    }

    public func submit() async {
        showsAllErrors = true
        guard canSubmit else { return }
        isSubmitting = true
        errorKind = nil
        defer { isSubmitting = false }
        do {
            let client = try await context.client()
            // A failed restore keeps nothing, so a retry calls it again on the same client.
            try await client.restoreFromRecovery(
                userId: RecoveryKit.normalizedUserId(userId), recoveryCode: Self.normalized(recoveryCode),
                revokeOthers: revokeOthers)
            guard let session = try await client.session() else { throw GimError.NotRegistered }
            recoveryCode = ""
            registration = Registration(client: client, config: context.config, session: session)
        } catch GimError.NotFound {
            errorKind = .notFound
        } catch GimError.Crypto {
            errorKind = .wrongCode
        } catch {
            errorKind = .error(ErrorPresenter.registrationKind(for: error))
        }
    }

    /// Signs in after the notice about chats was shown.
    public func finish() {
        guard let registration else { return }
        self.registration = nil
        context.onRegistered(registration)
    }

    private func kitChanged() {
        guard !kitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            parsed = nil
            return
        }
        let parsed = context.recoveryKit.parseRecoveryKit(text: kitText)
        self.parsed = parsed
        if let found = parsed.userId { userId = found }
        if let found = parsed.recoveryCode { recoveryCode = RecoveryKit.groupedRecoveryCode(found) }
    }

    /// Trims whitespace; gim-core's parser ignores case, `-` and whitespace inside the recovery code.
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
