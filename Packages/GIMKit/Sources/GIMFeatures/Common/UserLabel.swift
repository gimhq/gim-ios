import GIMClientKit

/// How users are labelled. Remote users may have no handle, and gim-core shows a user as its raw user id until the
/// directory lookup of its profile succeeds; neither should reach the screen as is.
public enum UserLabel {
    /// Characters of the user id shown by `shortUserId(_:)`.
    static let shortIdLength = 8

    /// The display name, else `@handle`, else the short user id.
    public static func name(for user: UserProfile) -> String {
        if !user.displayName.isEmpty, user.displayName != user.userId { return name(user.displayName) }
        if !user.handle.isEmpty { return "@\(user.handle)" }
        return shortUserId(user.userId)
    }

    /// The line under the name: `@handle`, else the short user id.
    public static func detail(for user: UserProfile) -> String {
        user.handle.isEmpty ? shortUserId(user.userId) : "@\(user.handle)"
    }

    /// A name gim-core rendered (chat names, message senders, membership changes): a raw user id becomes its short
    /// form, anything else is kept.
    public static func name(_ rendered: String) -> String {
        isUserId(rendered) ? shortUserId(rendered) : rendered
    }

    /// The first characters of the id after gim-core's `u` prefix, then "…": `u3k9x…` (56 characters) becomes
    /// `3k9x2abq…`. Ids that are not gim-core user ids are shortened the same way without dropping a prefix.
    public static func shortUserId(_ userId: String) -> String {
        let body = isUserId(userId) ? userId.dropFirst() : Substring(userId)
        guard body.count > shortIdLength else { return String(body) }
        return "\(body.prefix(shortIdLength))…"
    }

    /// gim-core user ids are `u` followed by 55 base32 characters (gim-core docs/identity.md).
    static func isUserId(_ value: String) -> Bool {
        value.count == 56 && value.first == "u"
            && value.dropFirst().allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
