import Foundation
import GIMClientKit
import Observation

/// The outcome of asking the device owner to authenticate (biometrics or the device passcode).
public enum DeviceAuthResult: Sendable, Hashable {
    case success
    /// The user cancelled the prompt.
    case cancelled
    /// The device has no passcode (or biometrics) to authenticate with.
    case unavailable
    /// Authentication failed (for example too many attempts).
    case failed
}

/// Asks the device owner to authenticate; the platform implements it (LocalAuthentication on Apple platforms).
public protocol DeviceAuthenticator: Sendable {
    /// `reason` is shown in the system prompt.
    func authenticate(reason: String) async -> DeviceAuthResult
}

/// Shows the recovery key kept on this device (`GimClientAPI.recoveryCode()`) like a wallet seed phrase: nothing until
/// the device owner authenticated, hidden again by `hide()` (leaving the screen, the app going to the background, a
/// screenshot or screen capture). A device without the key offers a new one through `rotation`, after which it can be
/// shown.
@MainActor
@Observable
public final class RecoveryKeyViewModel {
    public enum State: Sendable, Hashable {
        /// Nothing is shown; `reveal()` authenticates.
        case locked
        case authenticating
        /// The key is shown: `groupedCode`, `kitText`.
        case shown
        /// This device does not hold the key (linked by QR, or an account created before keys were kept); offer
        /// `rotation`.
        case notOnThisDevice
    }

    /// Why the key could not be shown; `text` gives the localized message.
    public enum ErrorKind: Sendable, Hashable {
        /// The device has no passcode to authenticate with.
        case noPasscode
        /// Authentication failed.
        case authenticationFailed
        /// An error of the client.
        case error(ErrorPresenter.Kind)

        public var text: String {
            switch self {
            case .noPasscode: onboardingText("Set a device passcode to see your recovery key.")
            case .authenticationFailed: onboardingText("Couldn't confirm it's you. Try again.")
            case .error(let kind): ErrorPresenter.text(for: kind)
            }
        }
    }

    public private(set) var state: State = .locked
    /// Error of the last `reveal()`.
    public private(set) var errorKind: ErrorKind?
    public var errorMessage: String? { errorKind?.text }
    public let userId: String
    public let labels: RecoveryKitLabels
    /// Creates a new key when this device has none; once its kit is confirmed, the key is kept here and can be shown.
    public let rotation: RecoveryKeyRotationViewModel

    /// The key while `state` is `shown`.
    @ObservationIgnored private var code: String?
    private let client: any GimClientAPI
    private let recoveryKit: any RecoveryKitFunctions
    private let authenticator: any DeviceAuthenticator

    public init(
        client: any GimClientAPI, userId: String, labels: RecoveryKitLabels = .localized,
        recoveryKit: any RecoveryKitFunctions, authenticator: any DeviceAuthenticator
    ) {
        self.client = client
        self.userId = userId
        self.labels = labels
        self.recoveryKit = recoveryKit
        self.authenticator = authenticator
        rotation = RecoveryKeyRotationViewModel(client: client, userId: userId, recoveryKit: recoveryKit)
        rotation.onKitConfirmed = { [weak self] in self?.newKeyConfirmed() }
    }

    /// The reason shown in the system authentication prompt.
    public static var authenticationReason: String { onboardingText("Show your recovery key") }

    /// The key in groups of four; empty unless `shown`.
    public var groupedCode: String {
        guard state == .shown, let code else { return "" }
        return RecoveryKit.groupedRecoveryCode(RecoveryKit.normalizedRecoveryCode(code))
    }

    /// The recovery kit text (Account ID and key) to copy, save or show as a QR code; empty unless `shown`.
    public var kitText: String {
        guard state == .shown, let code else { return "" }
        return recoveryKit.formatRecoveryKit(userId: userId, recoveryCode: code, labels: labels)
    }

    /// Authenticates the device owner, then reads the key kept on this device.
    public func reveal() async {
        guard state == .locked || state == .notOnThisDevice else { return }
        errorKind = nil
        state = .authenticating
        switch await authenticator.authenticate(reason: Self.authenticationReason) {
        case .success:
            break
        case .cancelled:
            state = .locked
            return
        case .unavailable:
            errorKind = .noPasscode
            state = .locked
            return
        case .failed:
            errorKind = .authenticationFailed
            state = .locked
            return
        }
        // Left the screen or went to the background while the prompt was up.
        guard state == .authenticating else { return }
        do {
            if let code = try client.recoveryCode() {
                self.code = code
                state = .shown
            } else {
                state = .notOnThisDevice
            }
        } catch {
            errorKind = .error(await ErrorPresenter.kind(for: error, client: client))
            state = .locked
        }
    }

    /// Drops the key from memory and shows nothing until the next `reveal()`; `notOnThisDevice` stays.
    public func hide() {
        code = nil
        if state != .notOnThisDevice { state = .locked }
    }

    /// The new key is kept on this device now: it can be shown after authenticating again.
    private func newKeyConfirmed() {
        code = nil
        state = .locked
    }
}
