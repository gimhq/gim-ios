import Foundation

/// The user ID: `"u"` + base32 (RFC 4648, lowercase, unpadded) of 34 bytes, from gim-core docs/identity.md
/// ("Identifiers"). Same rules as Android RecoveryInput.kt.
public enum UserID {
    private static let alphabet = "abcdefghijklmnopqrstuvwxyz234567"
    private static let length = 56

    /// Trims whitespace and lowercases (ids are canonical lowercase).
    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `^u[a-z2-7]{54}[aiqy]$` after `normalized` (as Android RecoveryInput.kt); 56 characters.
    public static func isValid(_ value: String) -> Bool {
        let symbols = Array(normalized(value))
        guard symbols.count == length, symbols[0] == "u", "aiqy".contains(symbols[length - 1]) else {
            return false
        }
        return symbols[1..<(length - 1)].allSatisfy(alphabet.contains)
    }

    /// The first token (maximal run of letters/digits) whose normalized form is a valid user ID, or nil.
    public static func firstValid(in text: String) -> String? {
        text.split { !($0.isLetter || $0.isNumber) }.first { isValid(String($0)) }.map { normalized(String($0)) }
    }
}
