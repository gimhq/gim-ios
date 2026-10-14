import Foundation

public enum AppDirectories {
    /// `Application Support/gim`: created on demand, excluded from backup and readable after the first unlock.
    public static var dataDirectory: URL {
        get throws {
            let fileManager = FileManager.default
            let base = try fileManager.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            var url = base.appendingPathComponent("gim", isDirectory: true)
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
}
