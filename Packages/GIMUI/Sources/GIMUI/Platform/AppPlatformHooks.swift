import Foundation
import GIMClientKit

/// The app's `PlatformHooks`: Keychain secrets, the app data directory and network reachability.
public final class AppPlatformHooks: PlatformHooks {
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

    public func secureStoreGet(key: String) -> Data? {
        keychain.secureStoreGet(key: key)
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
}
