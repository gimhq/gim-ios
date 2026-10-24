import Foundation
import GIMClientKit

/// Records every recovery-kit call and answers with `FakeRecoveryKitFunctions`, so tests can prove the view models use
/// the injected functions.
final class RecordingRecoveryKitFunctions: RecoveryKitFunctions, @unchecked Sendable {
    enum Call: Equatable {
        case format(userId: String, recoveryCode: String, labels: RecoveryKitLabels)
        case parse(text: String)
        case ending(recoveryCode: String)
        case matches(recoveryCode: String, typed: String)
    }

    private let lock = NSLock()
    private let base = FakeRecoveryKitFunctions()
    private var recorded: [Call] = []

    var calls: [Call] { lock.withLock { recorded } }

    func formatRecoveryKit(userId: String, recoveryCode: String, labels: RecoveryKitLabels) -> String {
        record(.format(userId: userId, recoveryCode: recoveryCode, labels: labels))
        return base.formatRecoveryKit(userId: userId, recoveryCode: recoveryCode, labels: labels)
    }

    func parseRecoveryKit(text: String) -> ParsedRecoveryKit {
        record(.parse(text: text))
        return base.parseRecoveryKit(text: text)
    }

    func recoveryKeyEnding(recoveryCode: String) -> String {
        record(.ending(recoveryCode: recoveryCode))
        return base.recoveryKeyEnding(recoveryCode: recoveryCode)
    }

    func matchesRecoveryKeyEnding(recoveryCode: String, typed: String) -> Bool {
        record(.matches(recoveryCode: recoveryCode, typed: typed))
        return base.matchesRecoveryKeyEnding(recoveryCode: recoveryCode, typed: typed)
    }

    private func record(_ call: Call) {
        lock.withLock { recorded.append(call) }
    }
}
