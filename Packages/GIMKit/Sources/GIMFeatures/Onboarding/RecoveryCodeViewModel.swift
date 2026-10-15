import Foundation
import Observation

/// Shows the recovery code once and makes the user re-enter one group of it before continuing. The code lives only
/// in memory and is dropped as soon as the confirmation succeeds.
@MainActor
@Observable
public final class RecoveryCodeViewModel {
    /// The code as returned by `createIdentity`; `nil` once confirmed.
    public private(set) var code: String?
    /// Zero-based index of the group the user must re-enter.
    public let confirmationGroupIndex: Int
    /// Whether the confirmation step is showing instead of the code.
    public private(set) var isConfirming = false
    public var confirmationInput = ""
    /// Message after a wrong group was entered.
    public private(set) var confirmationError: String?

    private let onConfirmed: @MainActor () -> Void

    /// - Parameters:
    ///   - code: the recovery code, groups separated by `-`.
    ///   - chooseGroup: picks the group to re-enter, given the number of groups.
    public init(code: String, chooseGroup: (Int) -> Int, onConfirmed: @escaping @MainActor () -> Void) {
        self.code = code
        let count = Self.groups(of: code).count
        confirmationGroupIndex = count > 0 ? min(max(chooseGroup(count), 0), count - 1) : 0
        self.onConfirmed = onConfirmed
    }

    /// The groups of the code as displayed; empty once confirmed.
    public var groups: [String] { code.map(Self.groups(of:)) ?? [] }

    /// The group number shown to the user, starting at 1.
    public var confirmationGroupNumber: Int { confirmationGroupIndex + 1 }

    public var isConfirmed: Bool { code == nil }

    /// Moves from the code to the confirmation step.
    public func continueToConfirmation() {
        guard !isConfirmed else { return }
        confirmationInput = ""
        confirmationError = nil
        isConfirming = true
    }

    /// Goes back to the code; only possible before the confirmation succeeded.
    public func showCodeAgain() {
        guard !isConfirmed else { return }
        confirmationError = nil
        isConfirming = false
    }

    /// Compares the entered group with the requested one, using the recovery code parsing rules.
    public func confirm() {
        let groups = groups
        guard isConfirming, groups.indices.contains(confirmationGroupIndex) else { return }
        let expected = groups[confirmationGroupIndex]
        guard Self.normalized(confirmationInput) == Self.normalized(expected) else {
            confirmationError = "That doesn't match group \(confirmationGroupNumber). Check what you wrote down."
            return
        }
        code = nil
        confirmationInput = ""
        confirmationError = nil
        onConfirmed()
    }

    static func groups(of code: String) -> [String] {
        code.split(separator: "-").map(String.init)
    }

    /// Like gim-core's recovery code parser: case-insensitive, `I`/`L` as `1`, `O` as `0`, `-` and whitespace
    /// ignored.
    static func normalized(_ text: String) -> String {
        String(
            text.uppercased().compactMap { character -> Character? in
                switch character {
                case "-": nil
                case _ where character.isWhitespace: nil
                case "I", "L": "1"
                case "O": "0"
                default: character
                }
            })
    }
}
