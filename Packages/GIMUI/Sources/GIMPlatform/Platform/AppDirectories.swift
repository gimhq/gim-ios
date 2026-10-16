import Foundation
import GIMClientKit

/// The App Group shared by the app and its Notification Service Extension (gim-core docs/API.md, "App extensions").
public enum AppGroup {
    public static let identifier = "group.im.g.apps"
    /// Last used server URL, written by the app and read by the extension for its `ClientConfig`.
    public static let serverUrlKey = "gim.serverUrl"

    /// The group's shared settings (`UserDefaults(suiteName:)`); `.standard` if the suite can't be opened.
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// The group container. Throws `GimError.Storage` when the App Group entitlement is missing.
    public static var containerURL: URL {
        get throws {
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
                throw GimError.Storage(reason: "App Group container \(identifier) is unavailable")
            }
            return url
        }
    }
}

public enum AppDirectories {
    /// `<App Group container>/gim`, shared by the app and the extension: created on demand, excluded from backup and
    /// readable after the first unlock.
    public static var dataDirectory: URL {
        get throws {
            let fileManager = FileManager.default
            var url = try AppGroup.containerURL.appendingPathComponent("gim", isDirectory: true)
            let protection: [FileAttributeKey: Any] = [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: protection)
            try fileManager.setAttributes(protection, ofItemAtPath: url.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            return url
        }
    }

    /// Removes `Application Support/gim`, the data directory before the App Group, best effort. Its state is not
    /// migrated: moving the data directory resets the local state, and gim-core starts with an empty one.
    public static func removeLegacyDataDirectory() {
        let fileManager = FileManager.default
        guard
            let base = try? fileManager.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return }
        let url = base.appendingPathComponent("gim", isDirectory: true)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }
}
