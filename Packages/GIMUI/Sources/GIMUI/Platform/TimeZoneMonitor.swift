import Foundation
import GIMClientKit

/// Keeps the attached client's date separators in the system time zone: sets it with `setLocalTimeZone(zone:)` on
/// `attach(_:)` and again on every `NSSystemTimeZoneDidChange`, each time as a new `SystemLocalTimeZone` (gim-core
/// caches the offsets of a zone object until it is replaced).
public final class TimeZoneMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private weak var client: (any GimClientAPI)?
    private let notificationCenter: NotificationCenter
    private var observer: (any NSObjectProtocol)?

    public init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            self?.systemTimeZoneChanged()
        }
    }

    deinit {
        if let observer { notificationCenter.removeObserver(observer) }
    }

    /// Sets the system time zone on `client` and keeps it updated; replaces the previously attached client.
    public func attach(_ client: any GimClientAPI) {
        lock.withLock { self.client = client }
        client.setLocalTimeZone(zone: SystemLocalTimeZone())
    }

    private func systemTimeZoneChanged() {
        NSTimeZone.resetSystemTimeZone()
        let client = lock.withLock { self.client }
        client?.setLocalTimeZone(zone: SystemLocalTimeZone())
    }
}

/// The system time zone when it was created. gim-core calls it on its callback thread; it only reads
/// Foundation's time zone data and never calls back into the client.
final class SystemLocalTimeZone: LocalTimeZone {
    private let zone = TimeZone.current

    func utcOffsetSecs(atMs: Int64) -> Int32 {
        Int32(zone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(atMs) / 1000)))
    }
}
