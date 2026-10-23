import Foundation
import GIMClientKit
import Observation

/// Restores the user on this device from the recovery code with the onboarding's client. A pasted recovery kit fills
/// the user ID and recovery code fields. After success it shows that chats are not rejoined automatically; dismissing
/// that notice signs in.
@MainActor
@Observable
public final class RestoreViewModel {
    /// The pasted recovery kit; each part found in it replaces its field.
    public var kitText = "" {
        didSet { if kitText != oldValue { kitChanged() } }
    }
    /// What the kit text contains; `nil` while it is blank.
    public private(set) var parsed: RecoveryKit.Parsed?
    /// Set by `enterSeparately()` to show the fields without a kit.
    public private(set) var showsSeparateFields = false
    public var userId = ""
    public var recoveryCode = ""
    /// Revokes every previously listed device of the user.
    public var revokeOthers = true

    public private(set) var isSubmitting = false
    /// Error from the last failed submission.
    public private(set) var errorMessage: String?
    /// Set by the first submit attempt so empty fields also show their messages.
    public private(set) var showsAllErrors = false
    /// Whether the restore succeeded and the notice about chats waits to be dismissed with `finish()`.
    public var showsRejoinNotice: Bool { registration != nil }

    public static let notFoundMessage = onboardingText(
        "This server has no account with this Account ID. Check the ID and the server.")
    public static let wrongCodeMessage = onboardingText(
        "This recovery key doesn't fit this account. Check the key and the Account ID.")
    public static let userIdMissingMessage = onboardingText("Enter your Account ID.")
    public static let recoveryCodeMissingMessage = onboardingText("Enter your recovery key.")
    public static let kitNotRecognizedMessage = onboardingText(
        "We couldn't find an Account ID or recovery key here. Paste the whole kit, or type them below.")
    public static let kitPartMissingMessage = onboardingText(
        "Part of the kit is missing. Fill in the empty field below.")

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
        guard let parsed else { return nil }
        switch (parsed.userId, parsed.recoveryCode) {
        case (.some, .some): return nil
        case (nil, nil): return Self.kitNotRecognizedMessage
        default: return Self.kitPartMissingMessage
        }
    }

    public func enterSeparately() {
        showsSeparateFields = true
    }

    /// Inline message for the user id field; `nil` while the field is untouched.
    public var userIdError: String? {
        guard showsAllErrors || !userId.isEmpty else { return nil }
        return Self.normalized(userId).isEmpty ? Self.userIdMissingMessage : nil
    }

    /// Inline message for the recovery code field; `nil` while the field is untouched. gim-core validates the format.
    public var recoveryCodeError: String? {
        guard showsAllErrors || !recoveryCode.isEmpty else { return nil }
        return Self.normalized(recoveryCode).isEmpty ? Self.recoveryCodeMissingMessage : nil
    }

    public var canSubmit: Bool {
        !Self.normalized(userId).isEmpty && !Self.normalized(recoveryCode).isEmpty && !isSubmitting
            && registration == nil
    }

    public func submit() async {
        showsAllErrors = true
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
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
            errorMessage = Self.notFoundMessage
        } catch GimError.Crypto {
            errorMessage = Self.wrongCodeMessage
        } catch {
            errorMessage = ErrorPresenter.registrationMessage(for: error)
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
        let parsed = RecoveryKit.parse(kitText)
        self.parsed = parsed
        if let found = parsed.userId { userId = found }
        if let found = parsed.recoveryCode { recoveryCode = RecoveryKit.groupedRecoveryCode(found) }
    }

    /// Trims whitespace; gim-core's parser ignores case, `-` and whitespace inside the recovery code.
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
