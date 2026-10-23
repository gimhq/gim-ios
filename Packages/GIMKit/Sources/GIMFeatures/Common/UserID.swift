import Foundation

/// Shape of a gim-core user id (shown as "Account ID"): "u" followed by 55 lowercase, unpadded RFC 4648 base32
/// symbols encoding 34 bytes, so the last symbol carries 3 zero bits. Same rule as the Android client.
public enum UserID {
    /// "u" plus 55 base32 symbols.
    static let length = 56
    private static let base32 = Set("abcdefghijklmnopqrstuvwxyz234567")
    /// Base32 symbols whose low 3 bits are zero.
    private static let lastSymbols = Set("aiqy")

    /// Trims whitespace and newlines and lowercases.
    public static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether `normalized(value)` matches `^u[a-z2-7]{54}[aiqy]$`.
    public static func isValid(_ value: String) -> Bool {
        let id = normalized(value)
        guard id.count == length, id.first == "u", let last = id.last, lastSymbols.contains(last) else {
            return false
        }
        return id.dropFirst().dropLast().allSatisfy(base32.contains)
    }

    /// The first valid id among the runs of ASCII letters and digits in `text`, normalized; `nil` without one. Finds
    /// the id in "Account ID: u…", "gim://u…/x" and a bare id.
    public static func firstValid(in text: String) -> String? {
        text.split(whereSeparator: { !isAlphanumeric($0) })
            .lazy
            .map { normalized(String($0)) }
            .first(where: isValid)
    }

    private static func isAlphanumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
