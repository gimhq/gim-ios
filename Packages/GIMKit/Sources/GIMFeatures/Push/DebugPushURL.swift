#if DEBUG
    import Foundation

    /// Debug builds only: `gim-debug://process-push?payload=<base64url JSON>` hands a push payload to the app, which
    /// runs the Notification Service Extension's `PushNotificationHandler` on it in-app. `simctl push` does not launch
    /// service extensions on the iOS 27 simulator, so the UI tests drive the extension's code path this way.
    ///
    /// `gim-debug://hold-sync` keeps the app's sync stopped until the next `process-push` has been handled, so that
    /// push is processed as the extension would while the app is not running: opening the `process-push` URL
    /// activates the app, and its own sync could otherwise join an invited chat first.
    public enum DebugPushURL {
        public static let scheme = "gim-debug"
        public static let host = "process-push"
        public static let holdSyncHost = "hold-sync"
        public static let holdSyncURL = URL(string: "\(scheme)://\(holdSyncHost)")!

        /// Whether `url` is `holdSyncURL`.
        public static func isHoldSync(_ url: URL) -> Bool {
            url.scheme == scheme && url.host == holdSyncHost
        }

        /// The URL carrying `payload` (JSON text), base64url-encoded without padding.
        public static func url(payload: String) -> URL {
            let encoded = Data(payload.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return URL(string: "\(scheme)://\(host)?payload=\(encoded)")!
        }

        /// The payload text of a `process-push` URL; `nil` for any other URL, a missing payload, invalid base64url or
        /// text that is not UTF-8.
        public static func payload(from url: URL) -> String? {
            guard url.scheme == scheme, url.host == host,
                let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == "payload" })?.value
            else { return nil }
            var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            guard let data = Data(base64Encoded: base64) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
#endif
