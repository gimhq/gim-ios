import Foundation
import GIMClientKit

/// Platform hooks that can erase everything they stored, as a backstop after signing out.
public protocol PlatformWiping {
    func wipe() throws
}

/// The app's `PlatformHooks`: Keychain secrets, the app data directory and network reachability.
public final class AppPlatformHooks: PlatformHooks, PlatformWiping {
    public let keychain: KeychainSecureStorage
    public let reachability: ReachabilityMonitor
    private let dataDirectory: String

    public init(
        dataDirectory: String,
        keychain: KeychainSecureStorage = KeychainSecureStorage(),
        reachability: ReachabilityMonitor = ReachabilityMonitor()
    ) {
        self.dataDirectory = dataDirectory
        self.keychain = keychain
        self.reachability = reachability
    }

    public func secureStoreGet(key: String) throws -> Data? {
        try keychain.secureStoreGet(key: key)
    }

    public func secureStoreSet(key: String, value: Data) throws {
        try keychain.secureStoreSet(key: key, value: value)
    }

    public func secureStoreDelete(key: String) {
        keychain.secureStoreDelete(key: key)
    }

    public func dataDir() -> String {
        dataDirectory
    }

    public func isNetworkReachable() -> Bool {
        reachability.isReachable
    }

    /// Deletes all Keychain items of the app's service and the contents of the data directory (keeping the
    /// directory itself).
    public func wipe() throws {
        try keychain.deleteAll()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: dataDirectory) else { return }
        for name in try fileManager.contentsOfDirectory(atPath: dataDirectory) {
            try fileManager.removeItem(atPath: (dataDirectory as NSString).appendingPathComponent(name))
        }
    }
}
