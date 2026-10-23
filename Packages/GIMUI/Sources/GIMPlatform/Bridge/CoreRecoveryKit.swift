import Foundation
import GIMClientKit
import GIMCore

/// gim-core's recovery-kit free functions behind `RecoveryKitFunctions`.
public struct CoreRecoveryKitFunctions: RecoveryKitFunctions {
    public init() {}

    public func formatRecoveryKit(
        userId: String, recoveryCode: String, labels: GIMClientKit.RecoveryKitLabels
    ) -> String {
        GIMCore.formatRecoveryKit(
            userId: userId, recoveryCode: recoveryCode, labels: GIMCore.RecoveryKitLabels(labels))
    }

    public func parseRecoveryKit(text: String) -> GIMClientKit.ParsedRecoveryKit {
        GIMClientKit.ParsedRecoveryKit(GIMCore.parseRecoveryKit(text: text))
    }

    public func recoveryKeyEnding(recoveryCode: String) -> String {
        GIMCore.recoveryKeyEnding(recoveryCode: recoveryCode)
    }

    public func matchesRecoveryKeyEnding(recoveryCode: String, typed: String) -> Bool {
        GIMCore.matchesRecoveryKeyEnding(recoveryCode: recoveryCode, typed: typed)
    }
}
