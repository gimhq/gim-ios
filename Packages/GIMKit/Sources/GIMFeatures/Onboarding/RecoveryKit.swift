import Foundation

/// Display helpers for the recovery kit. Formatting, parsing and the ending check are gim-core's
/// `RecoveryKitFunctions`, so every client reads and writes the same kit.
public enum RecoveryKit {
    public static let recoveryCodeGroup = 4
    /// The number of symbols the ending check asks for (gim-core: `recoveryKeyEnding`).
    public static let endingSymbols = 4

    /// What the user pasted or typed, trimmed and lowercased; same as `UserID.normalized(_:)`.
    public static func normalizedUserId(_ value: String) -> String {
        UserID.normalized(value)
    }

    /// The recovery code's symbols as gim-core parses them: `-` and whitespace dropped, uppercased, `I`/`L` -> `1`
    /// and `O` -> `0`. Other characters are kept so they can be flagged.
    public static func normalizedRecoveryCode(_ value: String) -> String {
        String(
            value.filter { $0 != "-" && !$0.isWhitespace }.uppercased().map { character -> Character in
                switch character {
                case "I", "L": "1"
                case "O": "0"
                default: character
                }
            })
    }

    /// Groups `symbols` in blocks of four separated by `-`, as gim-core displays the code.
    public static func groupedRecoveryCode(_ symbols: String) -> String {
        let characters = Array(symbols)
        return stride(from: 0, to: characters.count, by: recoveryCodeGroup)
            .map { String(characters[$0..<min($0 + recoveryCodeGroup, characters.count)]) }
            .joined(separator: "-")
    }
}
