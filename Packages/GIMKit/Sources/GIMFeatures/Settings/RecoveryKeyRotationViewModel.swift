import Foundation
import GIMClientKit
import Observation

/// Creates a new recovery key from Settings: asks for confirmation, rotates the recovery code and shows the new kit
/// with the onboarding check (`RecoveryKitViewModel`). The old key stops working on every server that takes the new
/// backup.
@MainActor
@Observable
public final class RecoveryKeyRotationViewModel {
    public enum State: Sendable, Hashable {
        case idle
        case confirming
        case rotating
        /// The new code; `kit` shows it until the user confirmed its ending.
        case showingKit(code: String)
        /// Error from the failed rotation, already localized by `ErrorPresenter`.
        case failed(String)
    }

    public private(set) var state: State = .idle
    /// The kit for the new code while `state` is `showingKit`.
    public private(set) var kit: RecoveryKitViewModel?
    /// Some servers did not take the new backup: the old key still works there until a later rotation reaches them.
    public private(set) var hasUnsyncedServers = false

    private let client: any GimClientAPI
    private let userId: String
    private let recoveryKit: any RecoveryKitFunctions
    /// Runs once the user confirmed the new kit's ending.
    @ObservationIgnored public var onKitConfirmed: (@MainActor () -> Void)?

    public init(client: any GimClientAPI, userId: String, recoveryKit: any RecoveryKitFunctions) {
        self.client = client
        self.userId = userId
        self.recoveryKit = recoveryKit
    }

    /// Asks the user to confirm.
    public func start() {
        guard state != .rotating, kit == nil else { return }
        hasUnsyncedServers = false
        state = .confirming
    }

    public func cancel() {
        guard state == .confirming else { return }
        state = .idle
    }

    /// Rotates the recovery code and shows the new kit.
    public func rotate() async {
        guard state != .rotating, kit == nil else { return }
        state = .rotating
        do {
            let rotation = try await client.rotateRecoveryCode()
            hasUnsyncedServers = !rotation.unsyncedHubIds.isEmpty
            kit = RecoveryKitViewModel(userId: userId, code: rotation.recoveryCode, recoveryKit: recoveryKit) {
                [weak self] in
                self?.kit = nil
                self?.state = .idle
                self?.onKitConfirmed?()
            }
            state = .showingKit(code: rotation.recoveryCode)
        } catch {
            state = .failed(await ErrorPresenter.message(for: error, client: client))
        }
    }
}
